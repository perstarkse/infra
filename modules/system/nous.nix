{...}: {
  config.flake.nixosModules.nous = {
    config,
    lib,
    pkgs,
    nous,
    ...
  }: let
    cfg = config.my.nous;
    nousPkg = nous.packages.${pkgs.system}.default;
  in {
    options.my.nous = {
      enable = lib.mkEnableOption "Enable Nous burnout prevention app";

      port = lib.mkOption {
        type = lib.types.port;
        default = 3002;
        description = "Port for Nous API server";
      };

      address = lib.mkOption {
        type = lib.types.str;
        default = "0.0.0.0";
        description = "Address for Nous to bind to";
      };

      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/nous";
        description = "Directory to store Nous data";
      };

      logLevel = lib.mkOption {
        type = lib.types.str;
        default = "info";
        description = "Log level (error, warn, info, debug, trace)";
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "https://nous.fyi";
        description = "Public URL of the application";
      };

      database = {
        host = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "PostgreSQL host";
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = 5432;
          description = "PostgreSQL port";
        };
        name = lib.mkOption {
          type = lib.types.str;
          default = "nous";
          description = "Database name";
        };
        user = lib.mkOption {
          type = lib.types.str;
          default = "nous";
          description = "Database user";
        };
      };

      smtp = {
        host = lib.mkOption {
          type = lib.types.str;
          default = "mail.smtp2go.com";
          description = "SMTP server host";
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = 587;
          description = "SMTP server port";
        };
      };

      s3 = {
        endpoint = lib.mkOption {
          type = lib.types.str;
          default = "http://127.0.0.1:3900";
          description = "S3 endpoint URL";
        };
        bucket = lib.mkOption {
          type = lib.types.str;
          default = "nous-backups";
          description = "S3 bucket name";
        };
        region = lib.mkOption {
          type = lib.types.str;
          default = "garage";
          description = "S3 region";
        };
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Open firewall for Nous port";
      };
    };

    config = lib.mkIf cfg.enable {
      clan.core.vars.generators.nous = {
        share = true;
        files = {
          env = {
            mode = "0400";
            neededFor = "users";
          };
        };
        prompts = {
          env = {
            description = "Nous environment file content";
            persist = true;
            type = "hidden";
          };
        };
        script = ''
          cp "$prompts/env" "$out/env"
        '';
      };

      # PostgreSQL database
      services.postgresql = {
        enable = true;
        ensureDatabases = [cfg.database.name];
        ensureUsers = [
          {
            name = cfg.database.user;
            ensureDBOwnership = true;
          }
        ];
      };

      # Nous systemd service
      systemd.services.nous = {
        description = "Nous - Burnout Prevention App";
        wantedBy = ["multi-user.target"];
        after = ["network.target" "postgresql.service" "garage.service"];
        requires = ["postgresql.service"];
        wants = ["garage.service"];

        serviceConfig = {
          Type = "simple";
          User = "nous";
          Group = "nous";
          WorkingDirectory = "${nousPkg}/share/nous";
          ExecStart = "${nousPkg}/bin/burnout_api start --server-and-worker";
          Restart = "always";
          RestartSec = "10";

          # Static environment
          Environment = [
            "LOCO_ENV=production"
            "PORT=${toString cfg.port}"
            "HOST=${cfg.host}"
            "RUST_LOG=garage=${cfg.logLevel},burnout_api=${cfg.logLevel}"
            "AWS_REGION=${cfg.s3.region}"
            "S3_BUCKET=${cfg.s3.bucket}"
            "S3_ENDPOINT=${cfg.s3.endpoint}"
            "SMTP_HOST=${cfg.smtp.host}"
            "SMTP_PORT=${toString cfg.smtp.port}"
            # Use peer auth via Unix socket - no password needed
            "DATABASE_URL=postgres:///${cfg.database.name}?host=/run/postgresql"
          ];

          # Secrets from environment file
          EnvironmentFile = [
            (config.my.secrets.getPath "nous" "env")
          ];
        };
      };

      # Create nous user and group
      users.users.nous = {
        isSystemUser = true;
        group = "nous";
        home = cfg.dataDir;
        createHome = true;
      };

      users.groups.nous = {};

      # Ensure data directory exists
      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir} 0755 nous nous -"
      ];

      # Firewall
      networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [cfg.port];
    };
  };
}
