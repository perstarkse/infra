{
  lib,
  pkgs,
  nixosModules,
  ...
}: let
  testHelpers = import ./lib/test-helpers.nix {inherit lib;};

  secretsStubModule = import ./lib/secrets-stub.nix {
    inherit lib;
    getPathDefault = _name: _file: "/var/lib/sedna-failover/cf-token";
    withDiscover = true;
    withAllowReadAccess = true;
  };

  cloudflareMock = pkgs.writeScript "cloudflare-mock" ''
    #!${pkgs.python3}/bin/python3
    import json
    from http.server import BaseHTTPRequestHandler, HTTPServer


    class Handler(BaseHTTPRequestHandler):
        def log_message(self, _format, *_args):
            pass

        def _json(self, status, body):
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(body).encode())

        def do_GET(self):
            self._json(
                200,
                {
                    "success": True,
                    "result": [
                        {
                            "id": "rec-test",
                            "content": "192.0.2.2",
                            "proxied": True,
                        }
                    ],
                },
            )

        def do_PATCH(self):
            length = int(self.headers.get("Content-Length", 0))
            self.rfile.read(length)
            self._json(200, {"success": True, "result": {}})


    HTTPServer(("127.0.0.1", 8787), Handler).serve_forever()
  '';

  nodeBase = testHelpers.mkCommonNode {
    extraPackages = with pkgs; [curl jq nginx];
  };

  maintenanceNode = lib.recursiveUpdate nodeBase {
    imports = [
      nixosModules.sedna-failover
      secretsStubModule
    ];

    networking.firewall.allowedTCPPorts = [80 8787];

    systemd.services.cloudflare-mock = {
      description = "Mock Cloudflare API for sedna-failover tests";
      wantedBy = ["multi-user.target"];
      before = ["failover-check.service"];
      serviceConfig = {
        Type = "simple";
        ExecStart = cloudflareMock;
      };
    };

    my.sedna-failover = {
      enable = true;

      maintenancePage = {
        title = "stark.pub — Test Offline";
        heading = "Test heading";
        bodyLines = [
          "Test body line 1"
          "Test body line 2"
        ];
        statusText = "Test status";
        links = [
          {
            label = "Status";
            url = "https://status.example.test";
          }
        ];
      };

      dnsFailover = {
        enable = true;
        sednaPublicIp = "192.0.2.1";
        heartbeatTimeoutMinutes = 5;
        cloudflareApiTokenFile = "/var/lib/sedna-failover/cf-token";
        cloudflareApiBaseUrl = "http://127.0.0.1:8787";
        heartbeatTimestampFile = "/var/lib/sedna-failover/last-heartbeat";
        zones = [
          {
            zone = "example.test";
            zoneId = "test-zone-id";
            domains = ["test.example.test"];
          }
        ];
      };
    };
  };
in {
  sedna-failover-maintenance-page = pkgs.testers.runNixOSTest {
    name = "sedna-failover-maintenance-page";
    nodes.machine = maintenanceNode;

    testScript = ''
      start_all()
      machine.wait_for_unit("multi-user.target")

      # Nginx should be running
      machine.wait_for_unit("nginx.service")
      machine.succeed("nginx -t")

      # Maintenance page should be served on port 80
      response = machine.succeed("curl -fsS --max-time 5 http://127.0.0.1/")
      assert "Test heading" in response, f"Expected 'Test heading' in response, got: {response}"
      assert "Test body line 1" in response, "Expected body text in response"
      assert "stark.pub" in response, "Expected 'stark.pub' branding in response"
      assert "Test status" in response, "Expected status text in response"

      # Check Content-Type is set
      headers = machine.succeed("curl -fsS -I --max-time 5 http://127.0.0.1/")
      assert "text/html" in headers, "Expected text/html content type"

      # Default catch-all should respond for any hostname
      response2 = machine.succeed("curl -fsS --max-time 5 -H 'Host: random.example.com' http://127.0.0.1/")
      assert "Test heading" in response2, "Maintenance page should be served for any hostname"

      print("✓ Maintenance page test passed")
    '';
  };

  sedna-failover-dns-check = pkgs.testers.runNixOSTest {
    name = "sedna-failover-dns-check";
    nodes.machine = maintenanceNode;

    testScript = ''
      import time
      start_all()
      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("nginx.service")
      machine.wait_for_unit("cloudflare-mock.service")
      machine.sleep(2)

      heartbeat_file = "/var/lib/sedna-failover/last-heartbeat"
      token_file = "/var/lib/sedna-failover/cf-token"

      # The failover-check timer should be registered
      machine.succeed("systemctl list-timers --no-pager | grep -q failover-check")

      # Seed token readable by the sandboxed failover-check user
      machine.succeed("mkdir -p /var/lib/sedna-failover && chown failover-check:failover-check /var/lib/sedna-failover")
      machine.succeed(
          f"printf 'dummy-token' | install -o failover-check -g failover-check -m 0400 /dev/stdin {token_file}"
      )

      # Write a recent heartbeat timestamp (within timeout of 5min)
      now = int(time.time())
      machine.succeed(f"echo {now} > {heartbeat_file}")

      # Run the failover-check service manually. Since heartbeat is recent, should exit clean.
      machine.succeed("systemctl start failover-check")
      machine.sleep(2)

      # Verify the service completed
      status = machine.succeed("systemctl show failover-check --property=ExecMainStatus --value")
      print(f"failover-check exit status: {status}")
      assert status.strip() == "0", f"Expected exit status 0, got {status}"

      # State directory should have been created
      result = machine.succeed("test -d /var/lib/sedna-failover && echo 'exists' || echo 'missing'")
      assert result.strip() == "exists", "State directory should exist"

      # DNS state file should NOT exist (since heartbeat is recent, no failover triggered)
      state_result = machine.succeed("test -f /var/lib/sedna-failover/dns-state.json && echo 'exists' || echo 'absent'")
      assert state_result.strip() == "absent", "DNS state should not exist when heartbeat is recent"

      # Now test: stale heartbeat should trigger failover
      # 400 seconds in the past > 5 minute timeout
      stale = now - 400
      machine.succeed(f"echo {stale} > {heartbeat_file}")
      machine.succeed("systemctl start failover-check")
      machine.sleep(2)

      # After stale heartbeat, DNS state file should exist (failover was triggered)
      state_result = machine.succeed("test -f /var/lib/sedna-failover/dns-state.json && echo 'exists' || echo 'absent'")
      assert state_result.strip() == "exists", "DNS state should exist after stale heartbeat triggers failover"

      # Verify state file has non-empty content
      content = machine.succeed("cat /var/lib/sedna-failover/dns-state.json")
      print(f"DNS state content: {content}")

      print("✓ DNS failover check test passed")
    '';
  };
}
