{
  config.flake.nixosModules.garage = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.garage;
  in {
    options.my.garage = {
      enable = lib.mkEnableOption "Enable Garage S3-compatible storage";

      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/garage/data";
        description = "Directory to store Garage data blocks";
      };

      metaDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/garage/meta";
        description = "Directory to store Garage metadata (use SSD if possible)";
      };

      s3Port = lib.mkOption {
        type = lib.types.port;
        default = 3900;
        description = "Port for S3 API";
      };

      rpcPort = lib.mkOption {
        type = lib.types.port;
        default = 3901;
        description = "Port for inter-node RPC";
      };

      adminPort = lib.mkOption {
        type = lib.types.port;
        default = 3903;
        description = "Port for admin API (localhost only)";
      };

      region = lib.mkOption {
        type = lib.types.str;
        default = "garage";
        description = "S3 region name";
      };

      replicationFactor = lib.mkOption {
        type = lib.types.int;
        default = 1;
        description = "Replication factor (1 for single-node)";
      };

      dbEngine = lib.mkOption {
        type = lib.types.enum ["sqlite" "lmdb"];
        default = "sqlite";
        description = "Database engine for metadata storage";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Open firewall for S3 API port";
      };
    };

    config = lib.mkIf cfg.enable {
      clan.core.vars.generators.garage = {
        share = true;
        files = {
          env = {
            mode = "0400";
            neededFor = "users";
          };
          "nous-access-key" = {
            mode = "0400";
            neededFor = "users";
          };
          "nous-secret-key" = {
            mode = "0400";
            neededFor = "users";
          };
        };
        prompts = {
          env = {
            description = "Garage environment file content";
            persist = true;
            type = "hidden";
          };
          "nous-access-key" = {
            description = "Nous access key content";
            persist = true;
            type = "hidden";
          };
          "nous-secret-key" = {
            description = "Nous secret key content";
            persist = true;
            type = "hidden";
          };
        };
        script = ''
          cp "$prompts/env" "$out/env"
          cp "$prompts/nous-access-key" "$out/nous-access-key"
          cp "$prompts/nous-secret-key" "$out/nous-secret-key"
        '';

      };

      # Use the built-in NixOS Garage module

      services.garage = {
        enable = true;
        package = pkgs.garage;

        # Environment file with RPC_SECRET and ADMIN_TOKEN
        environmentFile = config.my.secrets.getPath "garage" "env";

        settings = {
          metadata_dir = cfg.metaDir;
          data_dir = cfg.dataDir;
          db_engine = cfg.dbEngine;
          replication_factor = cfg.replicationFactor;

          rpc_bind_addr = "[::]:${toString cfg.rpcPort}";
          rpc_public_addr = "${config.my.listenNetworkAddress}:${toString cfg.rpcPort}";
          # rpc_secret is loaded from environmentFile as GARAGE_RPC_SECRET

          s3_api = {
            s3_region = cfg.region;
            api_bind_addr = "[::]:${toString cfg.s3Port}";
            root_domain = ".s3.garage.localhost";
          };

          admin = {
            api_bind_addr = "127.0.0.1:${toString cfg.adminPort}";
            # admin_token is loaded from environmentFile as GARAGE_ADMIN_TOKEN
          };
        };
      };

      # Ensure directories exist
      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir} 0755 root root -"
        "d ${cfg.metaDir} 0755 root root -"
      ];

      # Firewall
      networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [cfg.s3Port];
    };
  };
}
