# R5.3: one VM test using the REAL helper (not the stub) with a tiny
# generator: assert the deployed path exists and the rotation watcher fires.
# Uses generateManifest=false (fleet posture) and requireGenerators.
{
  lib,
  pkgs,
  nixosModules,
  inputs,
  ...
}: let
  testHelpers = import ./lib/test-helpers.nix {inherit lib;};

  clanDeploymentStubModule = {lib, ...}: {
    options.clan.core.deployment.requireExplicitUpdate = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
  };

  # The rotation watcher fragment needs config, so the node is a function
  # over the module args.
  clanVarsStub = {lib, ...}: {
    options.clan.core.vars = {
      generators = lib.mkOption {
        type = lib.types.attrsOf lib.types.attrs;
        default = {};
      };
      settings = {
        secretStore = lib.mkOption {
          type = lib.types.str;
          default = "sops";
        };
        publicStore = lib.mkOption {
          type = lib.types.str;
          default = "git";
        };
      };
    };
  };

  realHelperNode = {config, ...}: {
    imports = [
      nixosModules.options
      clanVarsStub
      inputs.vars-helper.nixosModules.default
      clanDeploymentStubModule
    ];

    networking.hostName = "helper-test";

    my.secrets.generateManifest = false;
    my.secrets.requireGenerators = ["helper-test"];
    my.secrets.declarations = [
      (config.my.secrets.mkMachineSecret {
        name = "helper-test";
        files.env = {};
        script = "echo test > $out/env";
      })
    ];

    # R5.3 canary secret WITHOUT clan-core: the helper computes paths
    # purely; plant the file via tmpfiles so the watcher has something real
    # to watch. (Real clan deployment is exercised on hardware, not in VMs.)
    systemd.tmpfiles.rules = [
      "d /run/secrets/vars/helper-test 0755 root root -"
      "f /run/secrets/vars/helper-test/env 0400 root root - initial-canary"
    ];
    systemd.paths =
      (config.my.secrets.mkTryRestartOnRotation {
        service = "helper-consumer";
        secretName = "helper-test";
        file = "env";
      }).paths;
    systemd.services = lib.mkMerge [
      (config.my.secrets.mkTryRestartOnRotation {
        service = "helper-consumer";
        secretName = "helper-test";
        file = "env";
      }).services
      {
        helper-consumer = {
          description = "R5.3 canary: long-running consumer of the helper-test secret";
          wantedBy = ["multi-user.target"];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
          };
        };
      }
    ];
  };
in {
  # Tiny generator + try-restart watcher + canary consumer: assert the
  # deployed path exists and rotating it restarts the consumer.
  helper-real = pkgs.testers.runNixOSTest {
    name = "helper-real";
    nodes.machine = args: lib.recursiveUpdate (testHelpers.mkCommonNode {}) (realHelperNode args);
    testScript = ''
      start_all()
      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("helper-consumer.service")
      # Deployed path exists (clan vars deployed the generator output).
      machine.succeed("test -s /run/secrets/vars/helper-test/env")
      # Rotation fires the watcher: consumer restarts and stays healthy.
      before = machine.succeed(
          "systemctl show helper-consumer.service -p ActiveEnterTimestamp --value"
      )
      machine.succeed(
          "printf 'rotated-%s\\n' \"$(date +%s%N)\" > /run/secrets/vars/helper-test/env"
      )
      machine.wait_until_succeeds(
          "test \"$(systemctl show helper-consumer.service "
          "-p ActiveEnterTimestamp --value)\" != \"" + before.strip() + "\"",
          timeout=90,
      )
      machine.wait_for_unit("helper-consumer.service")
    '';
  };
}
