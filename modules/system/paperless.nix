_: {
  config.flake.nixosModules.paperless = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.paperless;
  in {
    options.my.paperless = {
      enable = lib.mkEnableOption "Enable Paperless-ngx document management";

      port = lib.mkOption {
        type = lib.types.port;
        default = 28981;
        description = "Port to listen on";
      };

      address = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Address to bind to";
      };

      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/paperless";
        description = "Data directory for Paperless";
      };

      consumptionDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/paperless/consume";
        description = "Directory where Paperless watches for new documents";
      };

      mediaDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/paperless/media";
        description = "Directory for document storage";
      };

      url = lib.mkOption {
        type = lib.types.str;
        default = "http://localhost:28981";
        description = "Public URL of the Paperless instance";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Open firewall for the service port";
      };

      ocr = {
        language = lib.mkOption {
          type = lib.types.str;
          default = "swe+eng";
          description = "OCR languages (tesseract format)";
        };
      };

      database = {
        name = lib.mkOption {
          type = lib.types.str;
          default = "paperless";
          description = "Database name";
        };
        user = lib.mkOption {
          type = lib.types.str;
          default = "paperless";
          description = "Database user";
        };
        host = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "Database host (usually container local address)";
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = 5432;
          description = "Database port";
        };
        enableContainer = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable containerized PostgreSQL database";
        };
        container = {
          hostAddress = lib.mkOption {
            type = lib.types.str;
            default = "192.168.100.20";
            description = "Host address for the container bridge";
          };
          localAddress = lib.mkOption {
            type = lib.types.str;
            default = "192.168.100.22";
            description = "Container local address";
          };
        };
      };

      tika = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable Tika for parsing Office documents";
        };
      };

      s3Consumption = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Mount consumption directory from S3/Garage";
        };
        bucket = lib.mkOption {
          type = lib.types.str;
          default = "paperless-consume";
          description = "S3 bucket for consumption folder";
        };
        endpoint = lib.mkOption {
          type = lib.types.str;
          default = "http://127.0.0.1:3900";
          description = "S3 endpoint URL";
        };
        region = lib.mkOption {
          type = lib.types.str;
          default = "garage";
          description = "S3 region";
        };
      };
    };

    config = lib.mkIf cfg.enable {
      # Paperless-ngx service
      services.paperless = {
        enable = true;
        inherit (cfg) port;
        inherit (cfg) address;
        inherit (cfg) dataDir;
        inherit (cfg) consumptionDir;
        inherit (cfg) mediaDir;
        consumptionDirIsPublic = true;

        settings = {
          PAPERLESS_URL = cfg.url;
          PAPERLESS_OCR_LANGUAGE = cfg.ocr.language;
          PAPERLESS_OCR_MODE = "skip";
          PAPERLESS_OCR_USER_ARGS = {
            optimize = 1;
            pdfa_image_compression = "lossless";
          };
          PAPERLESS_CONSUMER_IGNORE_PATTERN = [
            ".DS_STORE/*"
            "desktop.ini"
            "._*"
            ".Trashes"
          ];

          # Database config
          PAPERLESS_DBENGINE = "postgresql";
          PAPERLESS_DBHOST = cfg.database.host;
          PAPERLESS_DBPORT = cfg.database.port;
          PAPERLESS_DBNAME = cfg.database.name;
          PAPERLESS_DBUSER = cfg.database.user;

          # Tika for Office docs
          PAPERLESS_TIKA_ENABLED = cfg.tika.enable;
          PAPERLESS_TIKA_ENDPOINT = "http://127.0.0.1:9998";
          PAPERLESS_TIKA_GOTENBERG_ENDPOINT = "http://127.0.0.1:3100";

          # Performance
          PAPERLESS_TASK_WORKERS = 2;
          PAPERLESS_THREADS_PER_WORKER = 2;

          # Logging
          PAPERLESS_LOGGING_DIR = "${cfg.dataDir}/log";
        };
      };

      # Redis for Paperless task queue
      services.redis.servers.paperless = {
        enable = true;
        port = 6379;
        bind = "127.0.0.1";
      };

      systemd = {
        services = {
          # Tika server for Office document parsing
          tika = lib.mkIf cfg.tika.enable {
            description = "Apache Tika Server";
            wantedBy = ["multi-user.target"];
            after = ["network.target"];
            serviceConfig = {
              Type = "simple";
              ExecStart = "${pkgs.tika}/bin/tika-server";
              Restart = "always";
              RestartSec = "10";
              DynamicUser = true;
            };
          };

          # Update Paperless service to depend on container and use correct DB host
          paperless-scheduler = lib.mkIf cfg.database.enableContainer {
            after = ["container@paperless-db.service"];
            wants = ["container@paperless-db.service"];
          };

          paperless-consumer = {
            after =
              lib.optionals cfg.database.enableContainer ["container@paperless-db.service"]
              ++ lib.optionals cfg.s3Consumption.enable ["paperless-consumption-mount.service"];
            wants =
              lib.optionals cfg.database.enableContainer ["container@paperless-db.service"]
              ++ lib.optionals cfg.s3Consumption.enable ["paperless-consumption-mount.service"];
          };

          paperless-task-queue = lib.mkIf cfg.database.enableContainer {
            after = ["container@paperless-db.service"];
            wants = ["container@paperless-db.service"];
          };

          paperless-web = lib.mkIf cfg.database.enableContainer {
            after = ["container@paperless-db.service"];
            wants = ["container@paperless-db.service"];
          };

          paperless-consumption-mount = lib.mkIf cfg.s3Consumption.enable (let
            accessKeyPath = config.my.secrets.getPath "garage-s3" "access_key_id";
            secretKeyPath = config.my.secrets.getPath "garage-s3" "secret_access_key";
            # Get paperless user/group IDs
            uid = toString config.users.users.paperless.uid;
            gid = toString config.users.groups.paperless.gid;
            mountScript = pkgs.writeShellScript "paperless-consumption-mount" ''
              set -euo pipefail
              export RCLONE_S3_ACCESS_KEY_ID="$(cat ${accessKeyPath})"
              export RCLONE_S3_SECRET_ACCESS_KEY="$(cat ${secretKeyPath})"
              exec ${pkgs.rclone}/bin/rclone mount \
                --config /dev/null \
                --s3-provider Other \
                --s3-endpoint ${cfg.s3Consumption.endpoint} \
                --s3-region ${cfg.s3Consumption.region} \
                --s3-no-check-bucket \
                --vfs-cache-mode writes \
                --vfs-cache-max-size 1G \
                --allow-other \
                --uid ${uid} \
                --gid ${gid} \
                --dir-perms 0775 \
                --file-perms 0664 \
                --dir-cache-time 1m \
                --poll-interval 30s \
                --vfs-write-back 5s \
                :s3:${cfg.s3Consumption.bucket} ${cfg.consumptionDir}
            '';
          in {
            description = "Rclone S3 Mount for Paperless Consumption";
            after = ["network-online.target"];
            wants = ["network-online.target"];
            wantedBy = ["multi-user.target"];
            before = ["paperless-consumer.service"];

            serviceConfig = {
              Type = "notify";
              ExecStartPre = [
                "${pkgs.coreutils}/bin/mkdir -p ${cfg.consumptionDir}"
                "-${pkgs.fuse}/bin/fusermount -u ${cfg.consumptionDir}"
              ];
              ExecStart = mountScript;
              ExecStop = "${pkgs.fuse}/bin/fusermount -u ${cfg.consumptionDir}";
              Restart = "on-failure";
              RestartSec = "10s";
            };
          });
        };

        # Directory setup (consumption dir needs 0770 and recursive ownership)
        tmpfiles.rules = [
          "d ${cfg.dataDir} 0750 paperless paperless -"
          "d ${cfg.consumptionDir} 0775 paperless paperless -"
          "Z ${cfg.consumptionDir} 0775 paperless paperless -"
          "d ${cfg.mediaDir} 0750 paperless paperless -"
          "d ${cfg.dataDir}/log 0750 paperless paperless -"
        ];
      };

      # Gotenberg for document conversion (port 3100 to avoid conflict with minne)
      virtualisation.oci-containers.containers.gotenberg = lib.mkIf cfg.tika.enable {
        image = "gotenberg/gotenberg:8";
        ports = ["127.0.0.1:3100:3000"];
        cmd = [
          "gotenberg"
          "--chromium-disable-javascript=true"
          "--chromium-allow-list=file:///tmp/.*"
        ];
      };

      # Firewall
      networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [cfg.port];

      # PostgreSQL container (isolated like politikerstod)
      containers.paperless-db = lib.mkIf cfg.database.enableContainer {
        autoStart = true;
        privateNetwork = true;
        inherit (cfg.database.container) hostAddress;
        inherit (cfg.database.container) localAddress;

        config = {
          pkgs,
          lib,
          ...
        }: {
          services.postgresql = {
            enable = true;
            enableTCPIP = true;
            settings.listen_addresses = lib.mkForce "*";

            authentication = pkgs.lib.mkOverride 10 ''
              # TYPE  DATABASE        USER            ADDRESS                 METHOD
              host    all             all             ${cfg.database.container.hostAddress}/32       trust
              host    all             all             169.254.0.0/16          trust
              local   all             all                                     peer
            '';

            ensureDatabases = [cfg.database.name];
            ensureUsers = [
              {
                name = cfg.database.user;
                ensureDBOwnership = false;
              }
            ];

            initialScript = pkgs.writeText "init-paperless-db" ''
              -- Grant database ownership
              ALTER DATABASE ${cfg.database.name} OWNER TO ${cfg.database.user};
              -- Connect to the database and fix schema permissions
              \c ${cfg.database.name}
              ALTER SCHEMA public OWNER TO ${cfg.database.user};
              GRANT ALL ON SCHEMA public TO ${cfg.database.user};
              GRANT CREATE ON SCHEMA public TO ${cfg.database.user};
            '';
          };

          systemd.services.fix-db-permissions = {
            description = "Fix DB permissions for paperless";
            after = ["postgresql.service"];
            requires = ["postgresql.service"];
            wantedBy = ["multi-user.target"];
            serviceConfig = {
              Type = "oneshot";
              User = "postgres";
              ExecStart = pkgs.writeShellScript "fix-paperless-db-perms" ''
                ${pkgs.postgresql}/bin/psql -d ${cfg.database.name} <<EOF
                ALTER SCHEMA public OWNER TO ${cfg.database.user};
                GRANT ALL ON SCHEMA public TO ${cfg.database.user};
                GRANT CREATE ON SCHEMA public TO ${cfg.database.user};
                EOF
              '';
            };
          };

          system.stateVersion = "24.05";
          networking.firewall.allowedTCPPorts = [5432];
        };
      };

      # S3 consumption mount (for distributed document ingestion)
      environment.systemPackages = lib.mkIf cfg.s3Consumption.enable [pkgs.rclone];

      my.secrets.allowReadAccess = lib.mkIf cfg.s3Consumption.enable [
        {
          readers = ["paperless"];
          path = config.my.secrets.getPath "garage-s3" "access_key_id";
        }
        {
          readers = ["paperless"];
          path = config.my.secrets.getPath "garage-s3" "secret_access_key";
        }
      ];

      programs.fuse.userAllowOther = lib.mkIf cfg.s3Consumption.enable true;
    };
  };
}
