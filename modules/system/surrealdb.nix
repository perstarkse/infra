{
  config.flake.nixosModules.surrealdb = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.surrealdb;
  in {
    options.my.surrealdb = {
      enable = lib.mkEnableOption "Enable SurrealDB service";

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Host address for SurrealDB to bind to";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 8220;
        description = "Port for SurrealDB to listen on";
      };

      database = lib.mkOption {
        type = lib.types.str;
        default = "minne_db";
        description = "Database name in SurrealDB";
      };

      namespace = lib.mkOption {
        type = lib.types.str;
        default = "minne_ns";
        description = "Namespace in SurrealDB";
      };

      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/surrealdb";
        description = "Directory to store SurrealDB data";
      };

      extraFlags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Additional flags to pass to SurrealDB";
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
          tcp = [8220];
          udp = [];
        };
        description = "Firewall port configuration for SurrealDB";
      };
    };

    config = lib.mkIf cfg.enable {
      # SurrealDB service configuration
      systemd.services.surrealdb = {
        description = "SurrealDB - Database Server";
        wantedBy = ["multi-user.target"];
        after = ["network.target"];

        serviceConfig = {
          Type = "simple";
          User = "surrealdb";
          Group = "surrealdb";
          WorkingDirectory = cfg.dataDir;
          ExecStart = ''${pkgs.surrealdb}/bin/surreal start --bind ${cfg.host}:${toString cfg.port} ${lib.concatStringsSep " " cfg.extraFlags} rocksdb:${cfg.dataDir}/data.db'';
          Restart = "always";
          RestartSec = "10";

          # Load environment file for credentials
          EnvironmentFile = [
            (config.my.secrets.getPath "surrealdb-credentials" "credentials")
          ];
        };
      };

      # Create surrealdb user and group
      users.users.surrealdb = {
        isSystemUser = true;
        group = "surrealdb";
        home = cfg.dataDir;
        createHome = true;
      };

      users.groups.surrealdb = {};

      # Firewall configuration
      networking.firewall.allowedTCPPorts = cfg.firewallPorts.tcp;
      networking.firewall.allowedUDPPorts = cfg.firewallPorts.udp;

      # Ensure data directory exists
      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir} 0755 surrealdb surrealdb -"
      ];
    };
  };
}
