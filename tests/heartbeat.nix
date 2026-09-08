{
  lib,
  pkgs,
  nixosModules,
  ...
}: let
  testHelpers = import ./lib/test-helpers.nix {inherit lib;};

  secretsStubModule = import ./lib/secrets-stub.nix {
    inherit lib;
    getPathDefault = name: file: "/etc/test-secrets/${name}/${file}";
    withDiscover = true;
    withAllowReadAccess = true;
  };

  # One mock stands in for both the local Gatus API (always 200 for the
  # right token, 401 otherwise) and ntfy (logs every POST).
  mockServer = pkgs.writeScript "heartbeat-mock" ''
    #!${pkgs.python3}/bin/python3
    import json
    from http.server import BaseHTTPRequestHandler, HTTPServer

    NTFY_LOG = "/tmp/ntfy.log"
    GATUS_TOKEN = "gatus-secret"


    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def _json(self, status, body):
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(body).encode())

        def do_POST(self):
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length) if length else b""
            if self.path.startswith("/api/v1/endpoints/"):
                auth = self.headers.get("Authorization", "")
                if auth == f"Bearer {GATUS_TOKEN}":
                    self._json(200, {"ok": True})
                else:
                    self._json(401, {"error": "unauthorized"})
                return
            if self.path.startswith("/ntfy/"):
                with open(NTFY_LOG, "a") as f:
                    title = self.headers.get("Title", "")
                    body_text = body.decode("utf-8", "replace")
                    f.write(f"POST {self.path} title={title} body={body_text}\n")
                self._json(200, {})
                return
            self._json(404, {})


    HTTPServer(("127.0.0.1", 18881), Handler).serve_forever()
  '';

  node = lib.recursiveUpdate (testHelpers.mkCommonNode {}) {
    imports = [
      nixosModules.options
      nixosModules.heartbeat
      secretsStubModule
    ];

    systemd.services.mock-server = {
      description = "Mock Gatus API + ntfy for heartbeat tests";
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "simple";
        ExecStart = mockServer;
      };
    };

    my.heartbeat = {
      receiver = {
        enable = true;
        listenAddress = "127.0.0.1";
        port = 18081;
        gatusPort = 18881;
        heartbeatTimestampFile = "/var/lib/heartbeat/last-heartbeat";
        gatusApiTokenEnvVar = "HEARTBEAT_GATUS_TOKEN";
      };
      push = {
        enable = true;
        endpointUrl = "http://127.0.0.1:18081/heartbeat";
        failureNtfy = {
          serverUrl = "http://127.0.0.1:18881/ntfy";
          topic = "test-heartbeat";
        };
      };
    };

    environment.etc."test-secrets/heartbeat/env" = {
      mode = "0400";
      text = ''
        HEARTBEAT_PUSH_TOKEN=push-secret
        HEARTBEAT_GATUS_TOKEN=gatus-secret
        HEARTBEAT_URL=http://unused.invalid/
      '';
    };
  };
in {
  heartbeat-push-receive-alert = pkgs.testers.runNixOSTest {
    name = "heartbeat-push-receive-alert";
    nodes.machine = node;

    testScript = ''
      import time
      start_all()
      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("mock-server.service")
      machine.wait_for_unit("heartbeat-receiver.service")
      machine.sleep(1)

      # Keep pushes manual: the hourly timer must not race the scenario.
      machine.succeed("systemctl stop heartbeat-push.timer")

      # 1. Happy path: push succeeds end to end (receiver auth with the push
      # token AND the gatus forward with the distinct gatus token — the mock
      # 401s anything else, and curl -f turns that into push failure).
      machine.succeed("systemctl start heartbeat-push.service")
      machine.wait_until_succeeds("test -f /var/lib/heartbeat/last-heartbeat", timeout=30)
      age = int(time.time()) - int(machine.succeed("cat /var/lib/heartbeat/last-heartbeat").strip())
      assert age < 60, f"timestamp should be fresh, age {age}s"
      machine.succeed("test ! -e /tmp/ntfy.log")
      print("✓ push succeeds with split tokens, no failure alert")

      # 2. Bearer separation at the receiver: the gatus token is NOT a valid
      # push credential, the push token is.
      code = machine.succeed(
          "curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Authorization: Bearer gatus-secret' http://127.0.0.1:18081/heartbeat"
      ).strip()
      assert code == "403", f"gatus token as push bearer should 403, got {code}"
      code = machine.succeed(
          "curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Authorization: Bearer push-secret' http://127.0.0.1:18081/heartbeat"
      ).strip()
      assert code == "204", f"push token should 204, got {code}"
      print("✓ push bearer and gatus token are separated")

      # 3. Break the path: stop the receiver, push fails, onFailure alerts once.
      machine.succeed("systemctl stop heartbeat-receiver.service")
      machine.succeed(
          "set +e; systemctl start heartbeat-push.service >/tmp/push.out 2>&1; echo $? > /tmp/push.code"
      )
      assert machine.succeed("cat /tmp/push.code").strip() != "0", "broken push must fail loudly"
      machine.wait_until_succeeds("test -f /tmp/ntfy.log", timeout=60)
      ntfy_log = machine.succeed("cat /tmp/ntfy.log")
      assert "test-heartbeat" in ntfy_log, f"failure alert should post to the topic:\\n{ntfy_log}"
      assert "failed" in ntfy_log, f"failure alert should say failed:\\n{ntfy_log}"
      machine.succeed("test -f /var/lib/heartbeat-push/failed")
      print("✓ failed push alerts once via onFailure")

      # 4. Still broken: a second failure must NOT re-alert (flapping guard).
      machine.succeed("systemctl reset-failed heartbeat-push.service")
      machine.succeed(
          "set +e; systemctl start heartbeat-push.service >/dev/null 2>&1; echo $? > /tmp/push2.code"
      )
      assert machine.succeed("cat /tmp/push2.code").strip() != "0", "second failure must still fail"
      machine.sleep(2)
      count = machine.succeed("grep -c 'test-heartbeat' /tmp/ntfy.log").strip()
      assert count == "1", f"expected exactly one failure alert, got {count}"
      print("✓ repeated failures do not re-alert")

      # 5. Heal: push succeeds, recovery is announced, flag cleared.
      machine.succeed("systemctl start heartbeat-receiver.service")
      machine.wait_until_succeeds("ss -ltn | grep -q ':18081 '", timeout=60)
      machine.succeed("systemctl start heartbeat-push.service")
      machine.wait_until_succeeds("grep -q 'recovered' /tmp/ntfy.log", timeout=60)
      machine.succeed("test ! -e /var/lib/heartbeat-push/failed")
      print("✓ recovery announced and flag cleared")
    '';
  };
}
