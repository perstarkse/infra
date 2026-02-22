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
      discover = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
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

  nodeBase = {
    networking = {
      useNetworkd = true;
      useDHCP = false;
      firewall.enable = false;
    };
    systemd.network.enable = true;
    system.stateVersion = "25.11";
  };

  serverNode = lib.recursiveUpdate nodeBase {
    virtualisation.vlans = [1];
    systemd.network.networks."10-eth1" = {
      matchConfig.Name = "eth1";
      address = ["10.0.0.1/24"];
      networkConfig.ConfigureWithoutCarrier = true;
    };

    services.openssh = {
      enable = true;
      settings.PasswordAuthentication = false;
      settings.PermitRootLogin = "yes";
    };
  };

  clientNode = lib.recursiveUpdate nodeBase {
    virtualisation.vlans = [1];
    imports = [nixosModules.wireguard-tunnels secretsStubModule];
    systemd.network.networks."10-eth1" = {
      matchConfig.Name = "eth1";
      address = ["10.0.0.15/24"];
      networkConfig.ConfigureWithoutCarrier = true;
    };

    my.wireguardTunnels = {
      enable = true;
      tunnels.genome-worktree-zenith = {
        enable = true;
        activationPolicy = "manual";
      };
    };

    environment.etc."test-secrets/wireguard-tunnels-genome-worktree-zenith/wg.conf" = {
      mode = "0400";
      text = ''
        [Interface]
        PrivateKey = KFjwd3aVdMJqJRT7ByNj5w+00iftHHE0xRqYgRQVCEc=
        Address = 10.7.0.2/32
        DNS = 1.1.1.1

        [Peer]
        PublicKey = Tx4IUngFH9q+qGdSr/BxIWnUlSbmWoxxRY+Juf/jnHs=
        AllowedIPs = 0.0.0.0/0
        Endpoint = 10.0.0.1:51820
        PersistentKeepalive = 25
      '';
    };

    environment.systemPackages = [pkgs.wireguard-tools];
  };
in {
  wireguard-system = pkgs.testers.runNixOSTest {
    name = "wireguard-system";
    nodes = {
      server = serverNode;
      client = clientNode;
    };

    testScript = ''
      start_all()

      server.wait_for_unit("sshd.service")
      client.wait_for_unit("systemd-networkd.service")

      client.succeed("systemctl start wg-tunnel-genome-worktree-zenith.service")
      client.wait_until_succeeds("systemctl is-active wg-tunnel-genome-worktree-zenith.service", timeout=60)
      client.succeed("ip link show wg >/dev/null")

      client.succeed("systemctl stop wg-tunnel-genome-worktree-zenith.service")
      client.wait_until_succeeds("! systemctl is-active wg-tunnel-genome-worktree-zenith.service", timeout=60)
    '';
  };
}
