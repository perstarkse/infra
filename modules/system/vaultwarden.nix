{
  config.flake.nixosModules.vaultwarden = {
    config,
    lib,
    mkStandardExposureOptions,
    ...
  }: let
    cfg = config.my.vaultwarden;
  in {
    options.my.vaultwarden = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Vaultwarden";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 8322;
        description = "Port for Vaultwarden to listen on";
      };

      address = lib.mkOption {
        type = lib.types.str;
        default = config.my.listenNetworkAddress;
        description = "Address for Vaultwarden to bind to (defaults to my.listenNetworkAddress)";
      };

      backupDir = lib.mkOption {
        type = lib.types.path;
        default = "/data/passwords";
        description = "Directory to store Vaultwarden data and backups";
      };

      firewallTcpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [8322];
        description = "Additional TCP ports to open for Vaultwarden.";
      };
      firewallUdpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [];
        description = "UDP ports to open for Vaultwarden.";
      };

      exposure =
        mkStandardExposureOptions {
          subject = "Vaultwarden";
          visibility = "internal";
          withAcmeDns01 = true;
          withRouter = true;
          withRouterTargetHost = true;
          withRouterDnsTarget = true;
        }
        // {
          cloudflareProxied = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Require generated reverse proxy traffic through Cloudflare or internal networks.";
          };
        };
    };

    config = {
      services.vaultwarden = {
        inherit (cfg) enable;
        inherit (cfg) backupDir;
        config = {
          ROCKET_PORT = cfg.port;
          ROCKET_ADDRESS = cfg.address;
        };
        environmentFile = config.my.secrets.getPath "vaultwarden" "env";
      };

      my.exposure.services.vaultwarden = lib.mkIf cfg.exposure.enable {
        upstream = {
          host = cfg.address;
          inherit (cfg) port;
        };
        router = {inherit (cfg.exposure.router) enable targets targetHost dnsTarget;};
        http.virtualHosts = lib.optional (cfg.exposure.domain != null) {
          inherit (cfg.exposure) domain;
          inherit (cfg.exposure) lanOnly cloudflareProxied useWildcard acmeDns01;
          websockets = true;
        };
        firewall.local = {
          enable = cfg.firewallTcpPorts != [] || cfg.firewallUdpPorts != [];
          tcp = cfg.firewallTcpPorts;
          udp = cfg.firewallUdpPorts;
        };
      };

      # Generate a secret for the Vaultwarden environment file
      my.secrets.declarations = [
        (config.my.secrets.mkMachineSecret {
          name = "vaultwarden";
          files = {
            "env" = {
              mode = "0400";
              additionalReaders = ["vaultwarden"];
            };
          };
          prompts."admin-token".input = {
            description = "Vaultwarden admin token";
            type = "hidden";
            persist = true;
          };
          script = ''
            set -euo pipefail
            umask 077
            mkdir -p "$out"
            echo "ADMIN_TOKEN=$(cat "$prompts/admin-token")" > "$out/env"
          '';
        })
      ];
    };
  };
}
