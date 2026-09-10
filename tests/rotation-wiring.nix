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
    mkMachineSecretDefault = spec: spec;
    withDiscover = true;
    withAllowReadAccess = true;
    withGenerateManifest = true;
  };

  # Every service here is long-running, so the assertion is the strong one:
  # rotating the watched file must actually advance the *target service's*
  # ActiveEnterTimestamp and leave it healthy — not merely run the rotation
  # unit. That is the property the hard-`restart` bug violated (the restart
  # unit failed and the service kept serving the stale secret).
  node =
    lib.recursiveUpdate (testHelpers.mkCommonNode {
      extraPackages = with pkgs; [curl mosquitto];
    }) {
      imports = [
        nixosModules.options
        nixosModules.mosquitto
        nixosModules.ntfy
        nixosModules.garage
        secretsStubModule
      ];

      my.garage = {
        enable = true;
        replicationMode = 1;
        bindAddress = "127.0.0.1";
        zone = "test";
      };

      my.mosquitto = {
        enable = true;
        secretName = "air-exhaust-mqtt";
        listeners = [
          {
            address = "127.0.0.1";
            port = 1883;
            settings = {allow_anonymous = false;};
          }
        ];
      };

      my.ntfy = {
        enable = true;
        secretName = "ntfy";
        address = "127.0.0.1";
        port = 2586;
        endpoints.enable = false;
      };

      # Stub secret file, created as a real (writable) file rather than a store
      # symlink so the test can rotate it in place.
      systemd.tmpfiles.rules = [
        "d /etc/test-secrets/ntfy 0755 root root -"
        "f /etc/test-secrets/ntfy/env 0644 root root -"
        "d /etc/test-secrets/garage 0755 root root -"
        "f /etc/test-secrets/garage/rpc_secret 0400 root root - 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
      ];
    };
in {
  # Generic harness: each row supplies (a) a command that rotates the watched
  # secret and (b) the service that must come back healthy. Adding a row
  # extends behavioural coverage to another watcher without a new VM test.
  rotation-wiring = pkgs.testers.runNixOSTest {
    name = "rotation-wiring";
    nodes.machine = node;

    testScript = ''
      import time

      start_all()
      machine.wait_for_unit("multi-user.target")

      def mint_hashes(set_id):
          """Write valid bcrypt hashes for all three MQTT users."""
          machine.succeed("rm -f /tmp/pw-*")
          for user in ["air-exhaust", "hass", "charon-ro"]:
              machine.succeed(
                  f"mosquitto_passwd -b -c /tmp/pw-{user} {user} hunter2-{set_id} && "
                  f"cut -d: -f2 < /tmp/pw-{user} > "
                  f"/etc/test-secrets/air-exhaust-mqtt/{user}.hash"
              )

      # mosquitto needs credential files before it can start.
      machine.succeed("systemctl stop mosquitto.service || true")
      machine.succeed("systemctl reset-failed mosquitto.service || true")
      machine.succeed("mkdir -p /etc/test-secrets/air-exhaust-mqtt")
      mint_hashes("A")
      machine.succeed("systemctl start mosquitto.service")

      def assert_rotation_restarts(label, rotate_cmd, restart_unit, service):
          """Run rotate_cmd; assert the target service restarted AND is healthy."""
          machine.wait_for_unit(service)
          machine.succeed(f"systemctl reset-failed {restart_unit} || true")
          before = machine.succeed(
              f"systemctl show {service} -p ActiveEnterTimestamp --value"
          )
          machine.succeed(rotate_cmd)

          deadline = time.time() + 90
          while True:
              after = machine.succeed(
                  f"systemctl show {service} -p ActiveEnterTimestamp --value"
              )
              if after != before:
                  break
              if time.time() >= deadline:
                  _, diag = machine.execute(
                      f"systemctl status {restart_unit} --no-pager -l; "
                      f"systemctl status {service} --no-pager -l | head -n 20"
                  )
                  raise AssertionError(
                      f"{label}: {service} did not restart after rotation; "
                      f"diagnostics:\n{diag}"
                  )
              time.sleep(2)

          # The restart must leave the service healthy, not merely "started
          # once": a bad secret that crash-loops the target is a failure of
          # the rotation, and this is the check that catches it.
          machine.wait_for_unit(service)
          deadline = time.time() + 30
          while True:
              state = machine.succeed(f"systemctl is-active {service}").strip()
              if state == "active":
                  break
              if time.time() >= deadline:
                  _, diag = machine.execute(
                      f"systemctl status {service} --no-pager -l | head -n 25"
                  )
                  raise AssertionError(
                      f"{label}: {service} not healthy after rotation:\n{diag}"
                  )
              time.sleep(2)
          print(f"OK {label}: {service} restarted via {restart_unit} and is active")

      # --- table of watchers under test -------------------------------------
      # 1. mosquitto: hashed MQTT credentials (the original incident).
      assert_rotation_restarts(
          "mosquitto",
          "rm -f /tmp/pw-*; for u in air-exhaust hass charon-ro; do "
          "mosquitto_passwd -b -c /tmp/pw-$u $u hunter2-B && "
          "cut -d: -f2 < /tmp/pw-$u > /etc/test-secrets/air-exhaust-mqtt/$u.hash; done",
          "mosquitto-hash-rotation-restart.service",
          "mosquitto.service",
      )

      # 2. ntfy: env file consumed once at startup by a long-running service.
      assert_rotation_restarts(
          "ntfy",
          "printf 'NTFY_BASE_URL=http://127.0.0.1\\nROTATED=%s\\n' \"$(date +%s%N)\""
          " > /etc/test-secrets/ntfy/env",
          "ntfy-env-rotation-restart.service",
          "ntfy-sh.service",
      )

      # 3. garage: clustered service reads rpc_secret only at startup; a
      # stale secret after rotation splits the cluster silently.
      assert_rotation_restarts(
          "garage",
          "printf '%s\\n' \"$(head -c 32 /dev/urandom | od -v -An -tx1 | tr -d ' \\n')\""
          " > /etc/test-secrets/garage/rpc_secret",
          "garage-rpc-rotation-restart.service",
          "garage.service",
      )

      # Credentials actually converged for mosquitto (not just a restart).
      machine.succeed(
          "mosquitto_pub -h 127.0.0.1 -p 1883 -u air-exhaust -P hunter2-B "
          "-t air-exhaust/fan/test -m 1"
      )
      machine.fail(
          "mosquitto_pub -h 127.0.0.1 -p 1883 -u air-exhaust -P hunter2-A "
          "-t air-exhaust/fan/test -m 1"
      )
    '';
  };
}
