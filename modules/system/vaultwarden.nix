{
  config.flake.nixosModules.vaultwarden = {
    config,
    lib,
    pkgs,
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
        default = "0.0.0.0";
        description = "Address for Vaultwarden to bind to";
      };

      backupDir = lib.mkOption {
        type = lib.types.path;
        default = "/data/passwords";
        description = "Directory to store Vaultwarden data and backups";
      };

      firewallPorts = lib.mkOption {
        type = lib.types.submodule {
          options = {
            tcp = lib.mkOption {
              type = lib.types.listOf lib.types.port;
              default = [];
              description = "TCP ports to allow through firewall";
            };
            udp = lib.mkOption {
              type = lib.types.listOf lib.types.port;
              default = [];
              description = "UDP ports to allow through firewall";
            };
          };
        };
        default = {
          tcp = [8322];
          udp = [];
        };
        description = "Firewall port configuration for Vaultwarden";
      };
    };

    config = {
      # Vaultwarden service configuration
      services.vaultwarden = {
        enable = cfg.enable;
        backupDir = cfg.backupDir;
        config = {
          ROCKET_PORT = cfg.port;
          ROCKET_ADDRESS = cfg.address;
        };
        environmentFile = config.my.secrets.getPath "vaultwarden" "env";
      };

      # Firewall configuration
      networking.firewall.allowedTCPPorts = cfg.firewallPorts.tcp;
      networking.firewall.allowedUDPPorts = cfg.firewallPorts.udp;

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
