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

      # Simplified disable options
      disable = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "List of k3s components to disable";
        example = ["traefik" "servicelb" "metrics-server"];
      };

      extraFlags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Extra flags to pass to k3s";
        example = ["--cluster-cidr=10.42.0.0/16"];
      };

      firewallPorts = lib.mkOption {
        type = lib.types.submodule {
          options = {
            tcp = lib.mkOption {
              type = lib.types.listOf lib.types.port;
              default = [6443 2379 2380 10250 10251 10252];
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
      # Use the standard NixOS k3s service with proper configuration
      services.k3s = {
        enable = true;
        role = "server";
        tokenFile = config.my.secrets.getPath "k3s" "token";
        clusterInit = cfg.initServer;
        serverAddr =
          if cfg.serverAddrs != []
          then lib.head cfg.serverAddrs
          else "";
        extraFlags =
          # Add TLS SAN
          (lib.optional (cfg.tlsSan != "") "--tls-san=${cfg.tlsSan}")
          # Add disable flags
          ++ (map (component: "--disable=${component}") cfg.disable)
          # Add any extra flags
          ++ cfg.extraFlags;
      };

      # Firewall configuration (ignored when using nftables, but needed for other machines)
      networking.firewall.allowedTCPPorts = cfg.firewallPorts.tcp;
      networking.firewall.allowedUDPPorts = cfg.firewallPorts.udp;
    };
  };
}
