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
        enable = true;
        package = pkgs.unstable.vaultwarden;
        backupDir = cfg.backupDir;
        config = {
          ROCKET_PORT = cfg.port;
          ROCKET_ADDRESS = cfg.address;
        };
        environmentFile = config.my.secrets."vaultwarden/env";
      };

      # Firewall configuration
      networking.firewall.allowedTCPPorts = cfg.firewallPorts.tcp;
      networking.firewall.allowedUDPPorts = cfg.firewallPorts.udp;

      # Restic backup configuration for Vaultwarden data
      services.restic.backups.vaultwarden = {
        initialize = true;

        environmentFile = config.my.secrets."restic-env-file/env";
        repositoryFile = config.my.secrets."restic-repo-file/vault-name";
        passwordFile = config.my.secrets."restic-password/password";

        paths = [
          cfg.backupDir
        ];

        pruneOpts = [
          "--keep-daily 7"
          "--keep-weekly 5"
          "--keep-monthly 12"
        ];
      };

      # Ensure backup directory exists
      systemd.tmpfiles.rules = [
        "d ${cfg.backupDir} 0755 vaultwarden vaultwarden -"
      ];
    };
  };
} 