{
  config.flake.nixosModules.k3s = {
    config,
    lib,
    ...
  }: let
    cfg = config.my.k3s;
  in {
    options.my.k3s = {
      enable = lib.mkEnableOption "Enable k3s cluster management";

      initServer = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether this node is the initial server node";
      };

      serverAddrs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "List of server addresses for joining nodes";
        example = ["https://10.0.0.1:6443"];
      };

      tlsSan = lib.mkOption {
        type = lib.types.str;
        default = "10.0.0.1";
        description = "TLS SAN for the k3s server";
      };

      disableServiceLb = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Disable the built-in service load balancer";
      };

      firewallPorts = lib.mkOption {
        type = lib.types.submodule {
          options = {
            tcp = lib.mkOption {
              type = lib.types.listOf lib.types.port;
              default = [6443 2379 2380];
              description = "TCP ports to allow in firewall";
            };
            udp = lib.mkOption {
              type = lib.types.listOf lib.types.port;
              default = [8472];
              description = "UDP ports to allow in firewall";
            };
          };
        };
        default = {};
        description = "Firewall port configuration for k3s";
      };
    };

    config = lib.mkIf cfg.enable {
      # Common flags for ALL server nodes
      _module.args.serverFlags = [
        "--tls-san ${cfg.tlsSan}"
      ] ++ lib.optionals cfg.disableServiceLb [
        "--disable=servicelb"
      ];

      # Firewall configuration
      networking.firewall.allowedTCPPorts = cfg.firewallPorts.tcp;
      networking.firewall.allowedUDPPorts = cfg.firewallPorts.udp;

      # k3s service configuration
      services.k3s = {
        enable = true;
        role = "server";
        tokenFile = config.my.secrets."k3s-token/password";
      } // (
        if cfg.initServer
        then {
          clusterInit = true;
          extraFlags = toString config._module.args.serverFlags;
        }
        else {
          serverAddr = lib.head cfg.serverAddrs;
          extraFlags = toString config._module.args.serverFlags;
        }
      );
    };
  };
} 