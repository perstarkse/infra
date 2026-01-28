_: {
  config.flake.nixosModules.garage = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.garage;
  in {
    options.my.garage = {
      enable = lib.mkEnableOption "Enable Garage S3 Service";

      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/garage/data";
        description = "Data directory for Garage";
      };

      metaDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/garage/meta";
        description = "Metadata directory for Garage";
      };

      s3Port = lib.mkOption {
        type = lib.types.int;
        default = 3900;
        description = "S3 API port";
      };

      rpcPort = lib.mkOption {
        type = lib.types.int;
        default = 3901;
        description = "RPC port for inter-node communication";
      };

      region = lib.mkOption {
        type = lib.types.str;
        default = "garage";
        description = "S3 region";
      };

      replicationMode = lib.mkOption {
        type = lib.types.int;
        default = 2;
        description = "Replication mode: 'none' for single node, or 2/3 for cluster";
      };

      rpcPublicAddr = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Public address for RPC (e.g., '10.0.0.1:3901'). Required for clustering.";
      };

      bootstrapPeers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "List of peer addresses to bootstrap from (e.g., ['node-id@10.0.0.2:3901'])";
      };

      zone = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Zone identifier for this node (used for data placement)";
      };
    };

    config = lib.mkIf cfg.enable {
      services.garage = {
        enable = true;
        package = pkgs.garage;
        settings =
          {
            metadata_dir = cfg.metaDir;
            data_dir = cfg.dataDir;
            rpc_secret_file = config.my.secrets.getPath "garage" "rpc_secret";
            replication_mode =
              if cfg.replicationMode == "none"
              then "none"
              else toString cfg.replicationMode;

            s3_api = {
              s3_region = cfg.region;
              api_bind_addr = "[::]:${toString cfg.s3Port}";
              root_domain = ".s3.garage";
            };

            s3_web = {
              bind_addr = "[::]:3902";
              root_domain = ".web.garage";
              enabled = true;
            };

            rpc_bind_addr = "[::]:${toString cfg.rpcPort}";
            admin = {
              api_bind_addr = "127.0.0.1:3903";
            };
          }
          // lib.optionalAttrs (cfg.rpcPublicAddr != null) {
            rpc_public_addr = cfg.rpcPublicAddr;
          }
          // lib.optionalAttrs (cfg.bootstrapPeers != []) {
            bootstrap_peers = cfg.bootstrapPeers;
          };
      };

      my.secrets.allowReadAccess = [
        {
          readers = ["garage"];
          path = config.my.secrets.getPath "garage" "rpc_secret";
        }
      ];

      systemd.services.garage.serviceConfig.DynamicUser = lib.mkForce false;

      systemd.services.garage.environment.GARAGE_ALLOW_WORLD_READABLE_SECRETS = "true";

      systemd.tmpfiles.rules = [
        "d /var/lib/garage 0700 garage garage -"
        "d ${cfg.dataDir} 0700 garage garage -"
        "d ${cfg.metaDir} 0700 garage garage -"
        "Z /var/lib/garage 0700 garage garage -"
        "Z ${cfg.dataDir} 0700 garage garage -"
        "Z ${cfg.metaDir} 0700 garage garage -"
      ];

      networking.firewall.allowedTCPPorts = [cfg.s3Port cfg.rpcPort 3902];

      users.users.garage = {
        isSystemUser = true;
        group = "garage";
        home = cfg.dataDir;
        createHome = true;
      };
      users.groups.garage = {};
    };
  };
}
