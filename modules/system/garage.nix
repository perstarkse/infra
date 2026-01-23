{ ... }: {
  config.flake.nixosModules.garage = { config, lib, pkgs, ... }: let
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

      region = lib.mkOption {
        type = lib.types.str;
        default = "garage";
        description = "S3 region";
      };
    };

  config = lib.mkIf cfg.enable {
    services.garage = {
      enable = true;
      package = pkgs.garage;
      settings = {
        metadata_dir = cfg.metaDir;
        data_dir = cfg.dataDir;
        rpc_secret_file = config.my.secrets.getPath "garage" "rpc_secret";
        replication_mode = "none";
        
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

        rpc_bind_addr = "[::]:3901";
        admin = {
          api_bind_addr = "127.0.0.1:3903";
        };
      };
    };

    my.secrets.allowReadAccess = [
      {
        readers = [ "garage" ];
        path = config.my.secrets.getPath "garage" "rpc_secret";
      }
    ];

    # Disable DynamicUser to ensure we use the static 'garage' user
    systemd.services.garage.serviceConfig.DynamicUser = lib.mkForce false;
    
    # Allow group-readable secrets (required because sops/vars-helper sets 0440)
    systemd.services.garage.environment.GARAGE_ALLOW_WORLD_READABLE_SECRETS = "true";

    # Ensure directories exist and have correct permissions
    systemd.tmpfiles.rules = [
      "d /var/lib/garage 0700 garage garage -"
      "d ${cfg.dataDir} 0700 garage garage -"
      "d ${cfg.metaDir} 0700 garage garage -"
      "Z /var/lib/garage 0700 garage garage -"
      "Z ${cfg.dataDir} 0700 garage garage -"
      "Z ${cfg.metaDir} 0700 garage garage -"
    ];

    # Open Firewall
    networking.firewall.allowedTCPPorts = [ cfg.s3Port 3901 3902 ];

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
