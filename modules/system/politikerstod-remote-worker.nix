{inputs, ...}: {
  config.flake.nixosModules.politikerstod-remote-worker = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.politikerstod-remote-worker;
    appPkg = inputs.politikerstod.packages.${pkgs.stdenv.hostPlatform.system}.default;

    # Build AUTH_ALLOWED_EMAIL_DOMAINS regex (same logic as main module)
    authAllowedRegex = let
      escapeForSystemd = s: builtins.replaceStrings ["\\" "$" "\""] ["\\\\" "$$" "\\\""] s;
    in
      "(?i)("
      + (builtins.concatStringsSep "|" (
        map (d: "@" + (escapeForSystemd (lib.strings.escapeRegex d)) + "$$") cfg.settings.authAllowedEmailDomains
      ))
      + ")";
  in {
    options.my.politikerstod-remote-worker = {
      enable = lib.mkEnableOption "Enable Politikerstöd remote worker (OCR + embeddings processing)";

      package = lib.mkOption {
        type = lib.types.package;
        default = appPkg;
        defaultText = lib.literalExpression "inputs.politikerstod.packages.${pkgs.stdenv.hostPlatform.system}.default";
        description = "Package providing the politikerstod-cli binary.";
      };

      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/politikerstod-worker";
        description = "Local state directory for worker (cache, logs)";
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

      # Remote connection settings
      database = {
        host = lib.mkOption {
          type = lib.types.str;
          default = "10.0.0.10";
          description = "Remote PostgreSQL host (makemake)";
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
      };

      # For OpenAI-based analysis workers (if they run here)
      openai = {
        model = lib.mkOption {
          type = lib.types.str;
          default = "gpt-4.1-mini";
          description = "OpenAI model for analysis";
        };
      };

      # Settings that the app requires at startup (even if not used by workers)
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

    config = lib.mkIf cfg.enable {
      # Secrets discovery - reuse existing politikerstod secrets or define new ones
      my.secrets.discover.includeTags = lib.mkAfter ["politikerstod"];

      systemd.services.politikerstod-worker = {
        description = "Politikerstöd Remote Worker (OCR + Embeddings)";
        wantedBy = ["multi-user.target"];
        after = ["network-online.target"];
        wants = ["network-online.target"];

        serviceConfig = {
          Type = "simple";
          User = "politikerstod-worker";
          Group = "politikerstod-worker";
          WorkingDirectory = cfg.dataDir;

          # Run worker-only mode
          ExecStart = let
            workerArgs =
              if cfg.workerTags != []
              then "--worker=${lib.concatStringsSep "," cfg.workerTags}"
              else "--worker";
          in "${cfg.package}/bin/politikerstod-cli start ${workerArgs}";

          Restart = "always";
          RestartSec = "10";

          # Environment configuration
          Environment = [
            "LOCO_ENV=production"
            # Database connection to remote makemake
            "DATABASE_URL=postgres://${cfg.database.user}@${cfg.database.host}:${toString cfg.database.port}/${cfg.database.name}"
            # S3 via router (Garage)
            "S3_ENDPOINT=${cfg.s3.endpoint}"
            "S3_BUCKET=${cfg.s3.bucket}"
            "AWS_REGION=${cfg.s3.region}"
            # Worker settings
            "LOG_LEVEL=${cfg.logLevel}"
            "NUM_WORKERS=${toString cfg.numWorkers}"
            "OPENAI_MODEL=${cfg.openai.model}"
            "FASTEMBED_CACHE_PATH=${cfg.dataDir}/fastembed_cache"
            # Required by app startup validation (even if not used by workers)
            "HOST=http://localhost"
            "PORT=5150"
            "CORS_ALLOW_ORIGIN=http://localhost"
            "AUTH_ALLOWED_EMAIL_DOMAINS=\"${authAllowedRegex}\""
            "SMTP_HOST=${cfg.smtp.host}"
            "SMTP_PORT=${toString cfg.smtp.port}"
            "MAILER_FROM=${cfg.smtp.from}"
            "PRETTY_BACKTRACE=false"
            "POLLING_HISTORICAL_MONTHS=${toString cfg.settings.pollingHistoricalMonths}"
            "EVALUATION_MODEL=${cfg.settings.evaluationModel}"
          ];

          # Secrets (S3 creds, OpenAI key)
          EnvironmentFile = [
            (config.my.secrets.getPath "politikerstod" "env")
          ];
        };
      };

      # User & group
      users.users.politikerstod-worker = {
        isSystemUser = true;
        group = "politikerstod-worker";
        home = cfg.dataDir;
        createHome = true;
      };
      users.groups.politikerstod-worker = {};

      # State directory
      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir} 0755 politikerstod-worker politikerstod-worker -"
        "d ${cfg.dataDir}/fastembed_cache 0755 politikerstod-worker politikerstod-worker -"
      ];
    };
  };
}
