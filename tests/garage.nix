{
  lib,
  pkgs,
  nixosModules,
  ...
}: let
  secretsStubModule = {lib, ...}: {
    options.my.secrets = {
      declarations = lib.mkOption {
        type = lib.types.listOf lib.types.anything;
        default = [];
      };
      allowReadAccess = lib.mkOption {
        type = lib.types.listOf lib.types.anything;
        default = [];
      };
      generateManifest = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      discover = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
        dir = lib.mkOption {
          type = lib.types.path;
          default = /tmp;
        };
        includeTags = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
        };
      };
      mkMachineSecret = lib.mkOption {
        type = lib.types.anything;
        default = spec: spec;
      };
      getPath = lib.mkOption {
        type = lib.types.anything;
        default = name: file: "/etc/test-secrets/${name}/${file}";
      };
    };
  };

  commonNode = {
    networking = {
      useNetworkd = true;
      useDHCP = false;
      firewall.enable = false;
    };
    systemd.network.enable = true;
    system.stateVersion = "25.11";
    environment.systemPackages = with pkgs; [
      curl
      garage
    ];
  };

  mkGarageNode = {
    ip,
    zone,
  }:
    lib.recursiveUpdate commonNode {
      virtualisation.vlans = [1];
      imports = [nixosModules.garage secretsStubModule];

      systemd.network.networks."10-eth1" = {
        matchConfig.Name = "eth1";
        address = ["${ip}/24"];
        networkConfig.ConfigureWithoutCarrier = true;
      };

      my.garage = {
        enable = true;
        replicationMode = 2;
        rpcPublicAddr = "${ip}:3901";
        inherit zone;
      };

      environment.etc."test-secrets/garage/rpc_secret" = {
        text = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
        mode = "0400";
      };
    };

  clientNode = lib.recursiveUpdate commonNode {
    virtualisation.vlans = [1];
    systemd.network.networks."10-eth1" = {
      matchConfig.Name = "eth1";
      address = ["10.0.0.20/24"];
      networkConfig.ConfigureWithoutCarrier = true;
    };
  };
in {
  garage-cluster = pkgs.testers.runNixOSTest {
    name = "garage-cluster";
    nodes = {
      io = mkGarageNode {
        ip = "10.0.0.1";
        zone = "io";
      };
      makemake = mkGarageNode {
        ip = "10.0.0.10";
        zone = "makemake";
      };
      client = clientNode;
    };

    testScript = ''
      start_all()

      io.wait_for_unit("garage.service")
      makemake.wait_for_unit("garage.service")

      io_id = io.succeed("garage node id -q | head -n1").strip()
      makemake_id = makemake.succeed("garage node id -q | head -n1").strip()

      io.succeed(f"garage node connect {makemake_id}")
      makemake.succeed(f"garage node connect {io_id}")

      io_id_short = io_id.split("@")[0][:16]
      makemake_id_short = makemake_id.split("@")[0][:16]

      io.succeed(f"garage layout assign -z io -c 1G {io_id_short}")
      io.succeed(f"garage layout assign -z makemake -c 1G {makemake_id_short}")
      io.succeed("garage layout apply --version 1")

      io.wait_until_succeeds("garage status | grep -qi healthy", timeout=120)
      makemake.wait_until_succeeds("garage status | grep -qi healthy", timeout=120)

      io.succeed("garage key create ci-key")
      io.succeed("garage bucket create ci-bucket")
      io.succeed("garage bucket allow --read --write --owner ci-bucket --key ci-key")

      makemake.wait_until_succeeds("garage key info ci-key >/dev/null", timeout=120)
      makemake.wait_until_succeeds("garage bucket info ci-bucket >/dev/null", timeout=120)
    '';
  };
}
