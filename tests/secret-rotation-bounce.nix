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

  node = lib.recursiveUpdate (testHelpers.mkCommonNode {}) {
    imports = [
      nixosModules.options
      nixosModules.mosquitto
      secretsStubModule
    ];

    environment.systemPackages = [pkgs.mosquitto];

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
  };
in {
  # Rotating the password hashes on disk must bounce mosquitto WITHOUT any
  # manual deploy step: the mosquitto-env-rotation path watcher fires and
  # the broker serves the new credentials (restartTriggers on /run/secrets
  # paths are inert — this test pins the working mechanism).
  secret-rotation-bounce = pkgs.testers.runNixOSTest {
    name = "secret-rotation-bounce";
    nodes.machine = node;

    testScript = ''
      import time

      start_all()
      machine.wait_for_unit("multi-user.target")
      # The broker cannot start until the stub secret files exist; stop
      # whatever state it is in, then mint credential set A.
      machine.succeed("systemctl stop mosquitto.service || true")
      machine.succeed("systemctl reset-failed mosquitto.service || true")
      machine.succeed("mkdir -p /etc/test-secrets/air-exhaust-mqtt")
      for user in ["air-exhaust", "hass", "charon-ro"]:
          machine.succeed(
              f"mosquitto_passwd -b -c /tmp/pw-{user} {user} hunter2-A && "
              f"cut -d: -f2 < /tmp/pw-{user} > "
              f"/etc/test-secrets/air-exhaust-mqtt/{user}.hash"
          )
      machine.succeed("systemctl start mosquitto.service")
      machine.wait_for_unit("mosquitto.service")

      def pub(user, password):
          return (
              f"mosquitto_pub -h 127.0.0.1 -p 1883 "
              f"-u {user} -P {password} "
              f"-t air-exhaust/fan/test -m 1"
          )

      # Set A authenticates before rotation.
      machine.succeed(pub("air-exhaust", "hunter2-A"))
      before = machine.succeed(
          "systemctl show mosquitto.service -p ActiveEnterTimestamp --value"
      )

      # Rotate all three hashes to credential set B (atomic replace, the way
      # clan re-deploys secrets). Drop the set-A temp files first:
      # mosquitto_passwd -c refuses to overwrite an existing file.
      machine.succeed("rm -f /tmp/pw-air-exhaust /tmp/pw-hass /tmp/pw-charon-ro")
      for user in ["air-exhaust", "hass", "charon-ro"]:
          machine.succeed(
              f"mosquitto_passwd -b -c /tmp/pw-{user} {user} hunter2-B && "
              f"cut -d: -f2 < /tmp/pw-{user} > "
              f"/etc/test-secrets/air-exhaust-mqtt/{user}.hash"
          )

      # The path watcher gives writes 5s to settle, then restarts the broker.
      deadline = time.time() + 90
      while True:
          after = machine.succeed(
              "systemctl show mosquitto.service -p ActiveEnterTimestamp --value"
          )
          if after != before:
              break
          if time.time() >= deadline:
              _, diag = machine.execute(
                  "systemctl status mosquitto-env-rotation.path --no-pager -l; "
                  "systemctl status mosquitto-env-rotation-restart.service --no-pager -l; "
                  "journalctl -u mosquitto-env-rotation.path --no-pager | tail -n 20; "
                  "systemctl list-units --all --no-pager | grep -i rotation"
              )
              raise AssertionError(
                  f"mosquitto never restarted after rotation; diagnostics:\n{diag}"
              )
          time.sleep(2)
      machine.wait_for_unit("mosquitto.service")

      # Set B authenticates, set A is refused — rotation converged.
      machine.succeed(pub("air-exhaust", "hunter2-B"))
      machine.fail(pub("air-exhaust", "hunter2-A"))
    '';
  };
}
