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

    REQUEST_LOG = "/tmp/cloudflare-requests.log"


    class Handler(BaseHTTPRequestHandler):
        def log_message(self, _format, *_args):
            pass

        # Tests write "broken-token" into the token file to simulate an invalid
        # Cloudflare API token.
        def _unauthorized(self):
            auth = self.headers.get("Authorization", "")
            return not auth.startswith("Bearer ") or auth == "Bearer broken-token"

        def _record(self):
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length).decode("utf-8") if length else ""
            with open(REQUEST_LOG, "a") as f:
                f.write(f"{self.command} {self.path} {body}\n")

        def _json(self, status, body):
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(body).encode())

        def _reject(self):
            self._json(
                403,
                {
                    "success": False,
                    "errors": [{"code": 9109, "message": "Invalid access token"}],
                },
            )

        def do_GET(self):
            self._record()
            if self._unauthorized():
                self._reject()
                return
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
            self._record()
            if self._unauthorized():
                self._reject()
                return
            self._json(200, {"success": True, "result": {}})


    HTTPServer(("127.0.0.1", 8787), Handler).serve_forever()
  '';

  nodeBase = testHelpers.mkCommonNode {
    extraPackages = with pkgs; [curl jq nginx];
  };

  maintenanceNode = lib.recursiveUpdate nodeBase {
    imports = [
      nixosModules.options
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

      tls.enable = false;

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

  sedna-failover-drill-dry-run = pkgs.testers.runNixOSTest {
    name = "sedna-failover-drill-dry-run";
    nodes.machine = maintenanceNode;

    testScript = ''
      import time
      start_all()
      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("cloudflare-mock.service")
      machine.sleep(2)

      heartbeat_file = "/var/lib/sedna-failover/last-heartbeat"
      token_file = "/var/lib/sedna-failover/cf-token"
      state_file = "/var/lib/sedna-failover/dns-state.json"
      request_log = "/tmp/cloudflare-requests.log"
      state_dir = "/var/lib/sedna-failover"

      script = machine.succeed("systemctl cat failover-check | grep '^ExecStart=' | head -n1 | cut -d= -f2").strip()
      print(f"health check script: {script}")

      # Token readable by the sandboxed failover-check user
      machine.succeed(f"mkdir -p {state_dir}")
      machine.succeed(
          f"printf 'dummy-token' | install -o failover-check -g failover-check -m 0400 /dev/stdin {token_file}"
      )

      # Seed a state file so the drill can prove it is not mutated
      machine.succeed(f"printf '[]' > {state_file}")

      # Simulate heartbeat loss: heartbeat 400s old, past the 5-minute timeout
      now = int(time.time())
      machine.succeed(f"echo {now - 400} > {heartbeat_file}")

      # Run the real failover-check service in dry-run mode via a runtime ExecStart override
      # (/etc/systemd/system is read-only on NixOS; systemd loads drop-ins from /run too)
      machine.succeed("mkdir -p /run/systemd/system/failover-check.service.d")
      machine.succeed(
          "printf '[Service]\\nExecStart=\\nExecStart=" + script + " --dry-run\\n' "
          "> /run/systemd/system/failover-check.service.d/drill.conf"
      )
      machine.succeed("systemctl daemon-reload")
      machine.succeed("systemctl start failover-check")
      machine.sleep(2)

      # Dry run must complete cleanly
      status = machine.succeed("systemctl show failover-check --property=ExecMainStatus --value")
      assert status.strip() == "0", f"dry-run drill failed with status {status}"

      # The decision path must have been the heartbeat-loss one
      journal = machine.succeed("journalctl -u failover-check --no-pager")
      assert "IO heartbeat lost! Triggering failover..." in journal, "drill should simulate heartbeat loss"
      assert "[dry-run] would PATCH test.example.test" in journal, (
          f"drill should show the would-be PATCH action, journal:\\n{journal}"
      )
      assert "=== Dry-run complete (no DNS changes made) ===" in journal, "dry run should report no changes"

      # Exact API sequence: record lookups only, zero PATCH requests
      api_log = machine.succeed(f"cat {request_log}")
      print("=== Cloudflare API request log (dry-run drill) ===")
      print(api_log)
      assert "GET /zones/test-zone-id/dns_records" in api_log, "dry run must look up the DNS record"
      assert "PATCH" not in api_log, "dry run must not issue PATCH requests"

      # State file untouched
      state = machine.succeed(f"cat {state_file}")
      assert state.strip() == "[]", f"dry run mutated the state file: {state}"

      print("✓ Dry-run failover drill passed: exact API sequence shown, no state mutation")
    '';
  };

  sedna-failover-drill-broken-token = pkgs.testers.runNixOSTest {
    name = "sedna-failover-drill-broken-token";
    nodes.machine = maintenanceNode;

    testScript = ''
      import time
      start_all()
      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("cloudflare-mock.service")
      machine.sleep(2)

      heartbeat_file = "/var/lib/sedna-failover/last-heartbeat"
      token_file = "/var/lib/sedna-failover/cf-token"
      state_dir = "/var/lib/sedna-failover"

      script = machine.succeed("systemctl cat failover-check | grep '^ExecStart=' | head -n1 | cut -d= -f2").strip()

      machine.succeed(f"mkdir -p {state_dir}")
      now = int(time.time())
      machine.succeed(f"echo {now - 400} > {heartbeat_file}")

      # Case 1: token file missing entirely — must fail loudly, not silently exit 0
      machine.succeed(f"set +e; {script} >/tmp/broken-missing.out 2>&1; echo $? > /tmp/broken-missing.code")
      code1 = machine.succeed("cat /tmp/broken-missing.code").strip()
      out1 = machine.succeed("cat /tmp/broken-missing.out")
      print(f"missing token file: exit {code1}")
      assert code1 != "0", f"missing token file must fail loudly, got exit {code1}: {out1}"
      assert "ERROR" in out1, f"missing token file should print an error: {out1}"

      # Case 2: invalid token — mock rejects with 403, curl -f must abort loudly
      machine.succeed(
          f"printf 'broken-token' | install -o failover-check -g failover-check -m 0400 /dev/stdin {token_file}"
      )
      machine.succeed(f"set +e; {script} >/tmp/broken-invalid.out 2>&1; echo $? > /tmp/broken-invalid.code")
      code2 = machine.succeed("cat /tmp/broken-invalid.code").strip()
      out2 = machine.succeed("cat /tmp/broken-invalid.out")
      print(f"invalid token: exit {code2}")
      assert code2 != "0", f"invalid token must fail loudly, got exit {code2}: {out2}"

      # Case 3: the deployed systemd service must surface the failure (alerting depends on it)
      machine.succeed(f"chown failover-check:failover-check {state_dir}")
      machine.succeed("set +e; systemctl start failover-check >/tmp/svc-start.out 2>&1; echo $? > /tmp/svc-start.code")
      code3 = machine.succeed("cat /tmp/svc-start.code").strip()
      status3 = machine.succeed("systemctl show failover-check --property=ExecMainStatus --value").strip()
      print(f"failover-check service with invalid token: start exit {code3}, ExecMainStatus {status3}")
      assert code3 != "0", "systemctl start should fail with an invalid token"
      assert status3 != "0", f"ExecMainStatus should be non-zero, got {status3}"

      # No failover state may be recorded by any of the broken runs
      state = machine.succeed(f"test -f {state_dir}/dns-state.json && echo exists || echo absent").strip()
      assert state == "absent", "broken-token runs must not write failover state"

      print("✓ Broken-token failover drill passed: both failure modes fail loudly")
    '';
  };
}
