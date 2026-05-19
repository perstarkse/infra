{inputs, ...}: {
  config.flake.nixosModules.politikerstod-remote-worker = {
    config,
    lib,
    pkgs,
    ...
  }: let
    appPkg = inputs.politikerstod.packages.${pkgs.stdenv.hostPlatform.system}.default;

    enabledInstances = lib.filterAttrs (_: i: i.enable) config.my.politikerstod-remote-worker.instances;

    mkWorkerEnv = name: instance: let
      escapeForSystemd = s: builtins.replaceStrings ["\\" "$" "\""] ["\\\\" "$$" "\\\""] s;
      domains = instance.settings.authAllowedEmailDomains or [];
      authAllowedRegex =
        if domains == ["*"] || domains == []
        then "@"
        else
          "(?i)("
          + (builtins.concatStringsSep "|" (
            map (d: "@" + (escapeForSystemd (lib.strings.escapeRegex d)) + "$$") domains
          ))
          + ")";
      dataDir = instance.dataDir or "/var/lib/politikerstod-worker-${name}";
    in [
      "LOCO_ENV=production"
      "DATABASE_URL=postgres://${instance.database.user or "politikerstod"}:@${instance.database.host or "10.0.0.10"}:${toString (instance.database.port or 5432)}/${instance.database.name or "politikerstod_prod"}"
      "S3_ENDPOINT=${instance.s3.endpoint or "http://10.0.0.1:3900"}"
      "S3_BUCKET=${instance.s3.bucket or "politikerstod-${name}"}"
      "AWS_REGION=${instance.s3.region or "garage"}"
      "S3_KEY_PREFIX=${instance.s3.prefix or ""}"
      "LEKEBERG_BASE_URL=${instance.scraper.baseUrl or ""}"
      "LOG_LEVEL=${instance.logLevel or "info"}"
      "NUM_WORKERS=${toString (instance.numWorkers or 4)}"
      "OPENAI_MODEL=${instance.openai.model or "gpt-4.1-mini"}"
      "FASTEMBED_CACHE_PATH=${dataDir}/fastembed_cache"
      "HOST=http://localhost"
      "PORT=5150"
      "CORS_ALLOW_ORIGIN=http://localhost"
      "AUTH_ALLOWED_EMAIL_DOMAINS=\"${authAllowedRegex}\""
      "SMTP_HOST=${instance.smtp.host or "smtp.example.com"}"
      "SMTP_PORT=${toString (instance.smtp.port or 587)}"
      "MAILER_FROM=${instance.smtp.from or "politikerstod@stark.pub"}"
      "PRETTY_BACKTRACE=false"
      "POLLING_HISTORICAL_MONTHS=${toString (instance.settings.pollingHistoricalMonths or 12)}"
      "EVALUATION_MODEL=${instance.settings.evaluationModel or "gpt-4o-mini"}"
    ];
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
              };
              port = lib.mkOption {
                type = lib.types.port;
                default = 5432;
              };
              name = lib.mkOption {
                type = lib.types.str;
                default = "politikerstod_prod";
              };
              user = lib.mkOption {
                type = lib.types.str;
                default = "politikerstod";
              };
            };

            s3 = {
              endpoint = lib.mkOption {
                type = lib.types.str;
                default = "http://10.0.0.1:3900";
              };
              bucket = lib.mkOption {
                type = lib.types.str;
                default = "politikerstod-${name}";
              };
              region = lib.mkOption {
                type = lib.types.str;
                default = "garage";
              };
              prefix = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = "S3 key prefix for logical isolation within a shared bucket. Unnecessary when each instance has its own bucket.";
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
              };
            };

            settings = {
              authAllowedEmailDomains = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = ["*"];
                description = "Allowed email domains for sign-up. Use [\"*\"] to accept all.";
              };
              evaluationModel = lib.mkOption {
                type = lib.types.str;
                default = "gpt-4o-mini";
              };
              pollingHistoricalMonths = lib.mkOption {
                type = lib.types.int;
                default = 12;
              };
            };

            smtp = {
              host = lib.mkOption {
                type = lib.types.str;
                default = "smtp.example.com";
              };
              port = lib.mkOption {
                type = lib.types.port;
                default = 587;
              };
              from = lib.mkOption {
                type = lib.types.str;
                default = "politikerstod@stark.pub";
              };
            };
          };
        }));
        default = {};
        description = "Politikerstod remote worker instances.";
      };
    };

    config = lib.mkMerge [
      (lib.mkIf (enabledInstances != {}) {
        systemd.services =
          lib.mapAttrs' (
            name: instance: let
              serviceName = "politikerstod-worker-${name}";
              userName = serviceName;
              groupName = serviceName;
              dataDir = instance.dataDir or "/var/lib/${serviceName}";
            in
              lib.nameValuePair serviceName {
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
                      if (instance.workerTags or []) != []
                      then "--worker=${lib.concatStringsSep "," (instance.workerTags or [])}"
                      else "--worker";
                  in "${config.my.politikerstod-remote-worker.package}/bin/politikerstod-cli start ${workerArgs}";

                  Restart = "always";
                  RestartSec = "10";

                  Environment = mkWorkerEnv name instance;

                  EnvironmentFile = [
                    (config.my.secrets.getPath (instance.secretsNamespace or "politikerstod-${name}") "env")
                  ];
                };
              }
          )
          enabledInstances;

        users.users =
          lib.mapAttrs' (
            name: instance: let
              userName = "politikerstod-worker-${name}";
              groupName = userName;
              dataDir = instance.dataDir or "/var/lib/politikerstod-worker-${name}";
            in
              lib.nameValuePair userName {
                isSystemUser = true;
                group = groupName;
                home = dataDir;
                createHome = true;
              }
          )
          enabledInstances;

        users.groups =
          lib.mapAttrs' (
            name: _:
              lib.nameValuePair "politikerstod-worker-${name}" {}
          )
          enabledInstances;

        systemd.tmpfiles.rules =
          lib.mapAttrsToList (name: instance: let
            userName = "politikerstod-worker-${name}";
            groupName = userName;
            dataDir = instance.dataDir or "/var/lib/politikerstod-worker-${name}";
          in ''
            d ${dataDir} 0755 ${userName} ${groupName} -
            d ${dataDir}/fastembed_cache 0755 ${userName} ${groupName} -
          '')
          enabledInstances;
      })
      {
        my.secrets.discover.includeTags = lib.mkAfter (
          lib.mapAttrsToList (
            name: instance:
              instance.secretsNamespace or "politikerstod-${name}"
          )
          enabledInstances
        );
      }
    ];
  };
}
