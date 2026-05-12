{inputs, ...}: {
  config.flake.nixosModules.politikerstod-remote-worker = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.politikerstod-remote-worker;
    appPkg = inputs.politikerstod.packages.${pkgs.stdenv.hostPlatform.system}.default;

    mkInstanceConfig = name: instance: let
      escapeForSystemd = s: builtins.replaceStrings ["\\" "$" "\""] ["\\\\" "$$" "\\\""] s;
      authAllowedRegex = "(?i)(" + (builtins.concatStringsSep "|" (
        map (d: "@" + (escapeForSystemd (lib.strings.escapeRegex d)) + "$$") instance.settings.authAllowedEmailDomains
      )) + ")";

      serviceName = "politikerstod-worker-${name}";
      userName = "politikerstod-worker-${name}";
      groupName = "politikerstod-worker-${name}";
      dataDir = instance.dataDir;
    in {
      systemd.services."${serviceName}" = {
        description = "Politikerstöd Remote Worker (${name}) — OCR + Embeddings";
        wantedBy = ["multi-user.target"];
        after = ["network-online.target"];
        wants = ["network-online.target"];

        serviceConfig = {
          Type = "simple";
          User = userName;
          Group = groupName;
          WorkingDirectory = dataDir;

          ExecStart = let
            workerArgs =
              if instance.workerTags != []
              then "--worker=${lib.concatStringsSep "," instance.workerTags}"
              else "--worker";
          in "${cfg.package}/bin/politikerstod-cli start ${workerArgs}";

          Restart = "always";
          RestartSec = "10";

          Environment = [
            "LOCO_ENV=production"
            "DATABASE_URL=postgres://${instance.database.user}@${instance.database.host}:${toString instance.database.port}/${instance.database.name}"
            "S3_ENDPOINT=${instance.s3.endpoint}"
            "S3_BUCKET=${instance.s3.bucket}"
            "AWS_REGION=${instance.s3.region}"
            "S3_KEY_PREFIX=${instance.s3.prefix}"
            "LEKEBERG_BASE_URL=${instance.scraper.baseUrl}"
            "LOG_LEVEL=${instance.logLevel}"
            "NUM_WORKERS=${toString instance.numWorkers}"
            "OPENAI_MODEL=${instance.openai.model}"
            "FASTEMBED_CACHE_PATH=${dataDir}/fastembed_cache"
            "HOST=http://localhost"
            "PORT=5150"
            "CORS_ALLOW_ORIGIN=http://localhost"
            "AUTH_ALLOWED_EMAIL_DOMAINS=\"${authAllowedRegex}\""
            "SMTP_HOST=${instance.smtp.host}"
            "SMTP_PORT=${toString instance.smtp.port}"
            "MAILER_FROM=${instance.smtp.from}"
            "PRETTY_BACKTRACE=false"
            "POLLING_HISTORICAL_MONTHS=${toString instance.settings.pollingHistoricalMonths}"
            "EVALUATION_MODEL=${instance.settings.evaluationModel}"
          ];

          EnvironmentFile = [
            (config.my.secrets.getPath instance.secretsNamespace "env")
          ];
        };
      };

      users.users."${userName}" = {
        isSystemUser = true;
        group = groupName;
        home = dataDir;
        createHome = true;
      };
      users.groups."${groupName}" = {};

      systemd.tmpfiles.rules = [
        "d ${dataDir} 0755 ${userName} ${groupName} -"
        "d ${dataDir}/fastembed_cache 0755 ${userName} ${groupName} -"
      ];
    };

    enabledInstances = lib.filterAttrs (_: instance: instance.enable) cfg.instances;
  in {
    options.my.politikerstod-remote-worker = {
      package = lib.mkOption {
        type = lib.types.package;
        default = appPkg;
        defaultText = lib.literalExpression "inputs.politikerstod.packages.${pkgs.stdenv.hostPlatform.system}.default";
        description = "Package providing the politikerstod-cli binary.";
      };

      instances = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
          options = {
            enable = lib.mkEnableOption "Politikerstöd remote worker instance ${name}";

            dataDir = lib.mkOption {
              type = lib.types.path;
              default = "/var/lib/politikerstod-worker-${name}";
              description = "Local state directory";
            };

            numWorkers = lib.mkOption {
              type = lib.types.int;
              default = 4;
              description = "Number of parallel worker threads";
            };

            workerTags = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [];
              description = "Optional: specific worker tags to run (empty = all workers)";
              example = ["document_process" "document_fetch"];
            };

            logLevel = lib.mkOption {
              type = lib.types.str;
              default = "info";
              description = "Log level (error, warn, info, debug, trace)";
            };

            secretsNamespace = lib.mkOption {
              type = lib.types.str;
              default = "politikerstod-${name}";
              description = "Clan vars secret namespace for this worker instance.";
            };

            database = {
              host = lib.mkOption {
                type = lib.types.str;
                default = "10.0.0.10";
                description = "Remote PostgreSQL host";
              };
              port = lib.mkOption {
                type = lib.types.port;
                default = 5432;
                description = "Remote PostgreSQL port";
              };
              name = lib.mkOption {
                type = lib.types.str;
                default = "politikerstod_prod";
                description = "Database name";
              };
              user = lib.mkOption {
                type = lib.types.str;
                default = "politikerstod";
                description = "Database user";
              };
            };

            s3 = {
              endpoint = lib.mkOption {
                type = lib.types.str;
                default = "http://10.0.0.1:3900";
                description = "Remote S3/Garage endpoint";
              };
              bucket = lib.mkOption {
                type = lib.types.str;
                default = "politikerstod";
                description = "S3 bucket name";
              };
              region = lib.mkOption {
                type = lib.types.str;
                default = "garage";
                description = "S3 region";
              };
              prefix = lib.mkOption {
                type = lib.types.str;
                description = "S3 key prefix (maps to S3_KEY_PREFIX env var). Must be set per instance.";
              };
            };

            scraper = {
              baseUrl = lib.mkOption {
                type = lib.types.str;
                description = "Scraper base URL (maps to LEKEBERG_BASE_URL env var). Must be set per instance.";
              };
            };

            openai = {
              model = lib.mkOption {
                type = lib.types.str;
                default = "gpt-4.1-mini";
                description = "OpenAI model for analysis";
              };
            };

            settings = {
              authAllowedEmailDomains = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = ["gmail.com" "hotmail.com" "lekeberg.se" "stark.pub"];
                description = "Allowed email domains for authentication (required by app startup)";
              };
              evaluationModel = lib.mkOption {
                type = lib.types.str;
                default = "gpt-4o-mini";
                description = "OpenAI model for evaluation";
              };
              pollingHistoricalMonths = lib.mkOption {
                type = lib.types.int;
                default = 12;
                description = "Months of historical data to poll";
              };
            };

            smtp = {
              host = lib.mkOption {
                type = lib.types.str;
                default = "smtp.example.com";
                description = "SMTP server host (required by app startup)";
              };
              port = lib.mkOption {
                type = lib.types.port;
                default = 587;
                description = "SMTP server port";
              };
              from = lib.mkOption {
                type = lib.types.str;
                default = "politikerstod@stark.pub";
                description = "Email sender address";
              };
            };
          };
        }));
        default = {};
        description = "Politikerstod remote worker instances. Each runs OCR/embedding processing for one instance.";
      };
    };

    config = lib.mkMerge (lib.mapAttrsToList mkInstanceConfig enabledInstances)
      // lib.mkIf (enabledInstances != {}) {
        my.secrets.discover.includeTags = lib.mkAfter (
          lib.mapAttrsToList (name: instance: instance.secretsNamespace) enabledInstances
        );
      };
  };
}
