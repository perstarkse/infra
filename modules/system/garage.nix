_: {
  config.flake.nixosModules.garage = {
    config,
    lib,
    pkgs,
    mkRestrictedPortRules,
    ...
  }: let
    cfg = config.my.garage;
    lanSources = ["10.0.0.0/8" "127.0.0.0/8"];
    mkPortRules = port: (mkRestrictedPortRules {inherit port; allowedSources = lanSources;}).iptables;
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

      bindAddress = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Local address the S3 API and RPC sockets bind to. Use the host LAN IP (e.g. 10.0.0.10) when other hosts or LAN consumers need S3/RPC; every S3 consumer must then point at that address, never 127.0.0.1.";
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
              api_bind_addr = "${cfg.bindAddress}:${toString cfg.s3Port}";
              root_domain = ".s3.garage";
            };

            rpc_bind_addr = "${cfg.bindAddress}:${toString cfg.rpcPort}";
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

      # No allowReadAccess for the garage user, and no
      # GARAGE_ALLOW_WORLD_READABLE_SECRETS override, by design. Garage
      # refuses secret files with group/other mode bits (mode & 0o077) but
      # runs as root here (no User= set, DynamicUser forced off), so it reads
      # the root-owned 0400 file directly. Granting access via setfacl was
      # actively harmful: the named-user ACE flips the ACL mask, which shows
      # up as group read bits (0440) and trips garage's check — the override
      # added in 87932fa was compensating for the ACL itself. Keep both gone.

      systemd = {
        services.garage = {
          serviceConfig.DynamicUser = lib.mkForce false;
        };

        tmpfiles.rules = [
          "d /var/lib/garage 0700 garage garage -"
          "d ${cfg.dataDir} 0700 garage garage -"
          "d ${cfg.metaDir} 0700 garage garage -"
          "Z /var/lib/garage 0700 garage garage -"
          "Z ${cfg.dataDir} 0700 garage garage -"
          "Z ${cfg.metaDir} 0700 garage garage -"
        ];
      };

      # LAN + loopback only. The router host (io) disables
      # networking.firewall entirely and governs these ports via its own
      # nftables (trusted-segment allow only), so this block is guarded to
      # plain-firewall hosts like makemake.
      networking.firewall = lib.mkIf config.networking.firewall.enable {
        extraCommands = lib.mkAfter (lib.concatStringsSep "\n" [
          (mkPortRules cfg.s3Port)
          (mkPortRules cfg.rpcPort)
        ]);
      };

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
