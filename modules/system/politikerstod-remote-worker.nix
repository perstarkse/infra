{inputs, ...}: {
  config.flake.nixosModules.politikerstod-remote-worker = {
    config,
    lib,
    pkgs,
    ...
  }: let
    appPkg = inputs.politikerstod.packages.${pkgs.stdenv.hostPlatform.system}.default;

    mkWorkerConfig = name: let
      i = config.my.politikerstod-remote-worker.instances.${name} or {};
      enabled = i.enable or false;
      escapeForSystemd = s: builtins.replaceStrings ["\\" "$" "\""] ["\\\\" "$$" "\\\""] s;
      authAllowedRegex = "(?i)(" + (builtins.concatStringsSep "|" (
        map (d: "@" + (escapeForSystemd (lib.strings.escapeRegex d)) + "$$") (i.settings.authAllowedEmailDomains or [])
      )) + ")";

      serviceName = "politikerstod-worker-${name}";
      userName = "politikerstod-worker-${name}";
      groupName = "politikerstod-worker-${name}";
      dataDir = i.dataDir or "/var/lib/politikerstod-worker-${name}";
    in
      lib.mkIf enabled {
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
                if (i.workerTags or []) != []
                then "--worker=${lib.concatStringsSep "," (i.workerTags or [])}"
                else "--worker";
            in "${config.my.politikerstod-remote-worker.package}/bin/politikerstod-cli start ${workerArgs}";

            Restart = "always";
            RestartSec = "10";

            Environment = [
              "LOCO_ENV=production"
              "DATABASE_URL=postgres://${i.database.user or "politikerstod"}:@${i.database.host or "10.0.0.10"}:${toString (i.database.port or 5432)}/${i.database.name or "politikerstod_prod"}"
              "S3_ENDPOINT=${i.s3.endpoint or "http://10.0.0.1:3900"}"
              "S3_BUCKET=${i.s3.bucket or "politikerstod"}"
              "AWS_REGION=${i.s3.region or "garage"}"
              "S3_KEY_PREFIX=${i.s3.prefix or ""}"
              "LEKEBERG_BASE_URL=${i.scraper.baseUrl or ""}"
              "LOG_LEVEL=${i.logLevel or "info"}"
              "NUM_WORKERS=${toString (i.numWorkers or 4)}"
              "OPENAI_MODEL=${i.openai.model or "gpt-4.1-mini"}"
              "FASTEMBED_CACHE_PATH=${dataDir}/fastembed_cache"
              "HOST=http://localhost"
              "PORT=5150"
              "CORS_ALLOW_ORIGIN=http://localhost"
              "AUTH_ALLOWED_EMAIL_DOMAINS=\"${authAllowedRegex}\""
              "SMTP_HOST=${i.smtp.host or "smtp.example.com"}"
              "SMTP_PORT=${toString (i.smtp.port or 587)}"
              "MAILER_FROM=${i.smtp.from or "politikerstod@stark.pub"}"
              "PRETTY_BACKTRACE=false"
              "POLLING_HISTORICAL_MONTHS=${toString (i.settings.pollingHistoricalMonths or 12)}"
              "EVALUATION_MODEL=${i.settings.evaluationModel or "gpt-4o-mini"}"
            ];

            EnvironmentFile = [
              (config.my.secrets.getPath (i.secretsNamespace or "politikerstod-${name}") "env")
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
              host = lib.mkOption { type = lib.types.str; default = "10.0.0.10"; };
              port = lib.mkOption { type = lib.types.port; default = 5432; };
              name = lib.mkOption { type = lib.types.str; default = "politikerstod_prod"; };
              user = lib.mkOption { type = lib.types.str; default = "politikerstod"; };
            };

            s3 = {
              endpoint = lib.mkOption { type = lib.types.str; default = "http://10.0.0.1:3900"; };
              bucket = lib.mkOption { type = lib.types.str; default = "politikerstod"; };
              region = lib.mkOption { type = lib.types.str; default = "garage"; };
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
              model = lib.mkOption { type = lib.types.str; default = "gpt-4.1-mini"; };
            };

            settings = {
              authAllowedEmailDomains = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = ["gmail.com" "hotmail.com" "lekeberg.se" "stark.pub"];
              };
              evaluationModel = lib.mkOption { type = lib.types.str; default = "gpt-4o-mini"; };
              pollingHistoricalMonths = lib.mkOption { type = lib.types.int; default = 12; };
            };

            smtp = {
              host = lib.mkOption { type = lib.types.str; default = "smtp.example.com"; };
              port = lib.mkOption { type = lib.types.port; default = 587; };
              from = lib.mkOption { type = lib.types.str; default = "politikerstod@stark.pub"; };
            };
          };
        }));
        default = {};
        description = "Politikerstod remote worker instances.";
      };
    };

    config = lib.mkMerge [
      (mkWorkerConfig "lekeberg")
      (mkWorkerConfig "orebro")
      {
        my.secrets.discover.includeTags = lib.mkAfter [
          (config.my.politikerstod-remote-worker.instances.lekeberg.secretsNamespace or "politikerstod-lekeberg")
          (config.my.politikerstod-remote-worker.instances.orebro.secretsNamespace or "politikerstod-orebro")
        ];
      }
    ];
  };
}
