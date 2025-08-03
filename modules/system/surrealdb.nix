{ inputs, ... }: {
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

      credentialsFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to file containing SurrealDB credentials (username and password)";
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
      services.surrealdb = {
        enable = true;
        package = pkgs.surrealdb;
        host = cfg.host;
        port = cfg.port;
        extraFlags = [
          "--log" "info"
          "file:${cfg.dataDir}/surrealdb.db"
        ] ++ cfg.extraFlags;
        
        # Load credentials from file if provided
        environmentFile = lib.mkIf (cfg.credentialsFile != null) [
          cfg.credentialsFile
        ];
      };

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