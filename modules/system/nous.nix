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
          default = "mail-eu.smtp2go.com";
          description = "SMTP server host";
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = 587;
          description = "SMTP server port (587 for STARTTLS)";
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
            # Cannot use ensureDBOwnership when db name != user name
            ensureDBOwnership = false;
          }
        ];
        # Allow local socket connections without password (peer auth)
        authentication = pkgs.lib.mkOverride 10 ''
          # TYPE  DATABASE        USER            ADDRESS                 METHOD
          local   all             all                                     peer
          host    all             all             127.0.0.1/32            scram-sha-256
          host    all             all             ::1/128                 scram-sha-256
        '';
        # Grant ownership of the database to the user
        initialScript = pkgs.writeText "nous-db-init" ''
          DO $$
          BEGIN
            IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${cfg.database.user}') THEN
              CREATE ROLE "${cfg.database.user}" WITH LOGIN;
            END IF;
          END
          $$;
          GRANT ALL PRIVILEGES ON DATABASE "${cfg.database.name}" TO "${cfg.database.user}";
          ALTER DATABASE "${cfg.database.name}" OWNER TO "${cfg.database.user}";
          \c "${cfg.database.name}"
          GRANT ALL ON SCHEMA public TO "${cfg.database.user}";
          ALTER SCHEMA public OWNER TO "${cfg.database.user}";
        '';
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
          ExecStart = "${nousPkg}/bin/nous_api start --server-and-worker";
          Restart = "always";
          RestartSec = "10";

          # Static environment
          Environment = [
            "LOCO_ENV=production"
            "PORT=${toString cfg.port}"
            "HOST=${cfg.host}"
            "RUST_LOG=garage=${cfg.logLevel},nous_api=${cfg.logLevel},loco_rs=${cfg.logLevel}"
            "AWS_REGION=${cfg.s3.region}"
            "S3_BUCKET=${cfg.s3.bucket}"
            "S3_ENDPOINT=${cfg.s3.endpoint}"
            "SMTP_HOST=${cfg.smtp.host}"
            "SMTP_PORT=${toString cfg.smtp.port}"
            # Use peer auth via Unix socket (no password needed)
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
