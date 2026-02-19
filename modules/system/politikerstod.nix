{inputs, ...}: {
  config.flake.nixosModules.politikerstod = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.politikerstod;
    # Access the package from inputs
    appPkg = inputs.politikerstod.packages.${pkgs.stdenv.hostPlatform.system}.default;

    authAllowedRegex = let
      # Escape characters for systemd's double-quoted Environment value:
      # \  -> \\
      # $  -> $$
      # "  -> \"
      escapeForSystemd = s: builtins.replaceStrings ["\\" "$" "\""] ["\\\\" "$$" "\\\""] s;
    in
      "(?i)("
      + (builtins.concatStringsSep "|" (
        map (d: "@" + (escapeForSystemd (lib.strings.escapeRegex d)) + "$$") cfg.settings.authAllowedEmailDomains
      ))
      + ")";
  in {
    options.my.politikerstod = {
      enable = lib.mkEnableOption "Enable Politikerstöd Service";

      port = lib.mkOption {
        type = lib.types.port;
        default = 5150;
        description = "Port to listen on";
      };

      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/politikerstod";
        description = "State directory";
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "http://localhost:5150";
        description = "Public URL of the application";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Open firewall for the service port";
      };

      database = {
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
        host = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "Database host";
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = 5432;
          description = "Database port";
        };
        enableContainer = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable local database container";
        };
        allowedHosts = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "Additional hosts allowed to connect to the database (e.g., remote workers)";
          example = ["10.0.0.15"];
        };
        container = {
          hostAddress = lib.mkOption {
            type = lib.types.str;
            default = "192.168.100.10";
            description = "Host address for the container bridge";
          };
          localAddress = lib.mkOption {
            type = lib.types.str;
            default = "192.168.100.12";
            description = "Container local address";
          };
        };
      };

      smtp = {
        host = lib.mkOption {
          type = lib.types.str;
          default = "smtp.example.com";
          description = "SMTP server host";
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = 587;
          description = "SMTP server port";
        };
        secure = lib.mkOption {
          type = lib.types.bool;
          default = false; # Changed from true
          description = "Use secure connection (TLS)";
        };
        from = lib.mkOption {
          type = lib.types.str;
          default = "politikerstod@stark.pub";
          description = "Email sender address";
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
          default = "politikerstod";
          description = "S3 bucket name";
        };
        region = lib.mkOption {
          type = lib.types.str;
          default = "garage";
          description = "S3 region";
        };
      };

      settings = {
        logLevel = lib.mkOption {
          type = lib.types.str;
          default = "info";
          description = "Log level (error, warn, info, debug, trace)";
        };
        prettyBacktrace = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable pretty backtrace";
        };
        numWorkers = lib.mkOption {
          type = lib.types.int;
          default = 2;
          description = "Number of background workers";
        };
        pollingHistoricalMonths = lib.mkOption {
          type = lib.types.int;
          default = 12;
          description = "Months of historical data to poll";
        };
        openaiModel = lib.mkOption {
          type = lib.types.str;
          default = "gpt-4o-mini";
          description = "OpenAI model to use for analysis";
        };
        evaluationModel = lib.mkOption {
          type = lib.types.str;
          default = "gpt-4o-mini";
          description = "OpenAI model to use for evaluation";
        };
        authAllowedEmailDomains = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = ["gmail.com" "hotmail.com" "lekeberg.se" "stark.pub"];
          description = "Allowed email domains for authentication";
        };
      };
    };

    config = lib.mkIf cfg.enable {
      systemd.services.politikerstod = {
        description = "Politikerstöd Service";
        wantedBy = ["multi-user.target"];
        after = ["network.target"];
        # requires = ["politikerstod-s3-setup.service"];

        serviceConfig = {
          Type = "simple";
          User = "politikerstod";
          Group = "politikerstod";
          WorkingDirectory = cfg.dataDir;
          # Run the binary
          ExecStart = "${appPkg}/bin/politikerstod-cli start --all";
          Restart = "always";
          RestartSec = "10";

          # Pass non-secret config via Environment
          Environment = [
            "LOCO_ENV=production"
            "PORT=${toString cfg.port}"
            "HOST=${cfg.host}"
            "CORS_ALLOW_ORIGIN=${cfg.host}"
            "DATABASE_URL=postgres://${cfg.database.user}@${cfg.database.host}:${toString cfg.database.port}/${cfg.database.name}"
            "SMTP_HOST=${cfg.smtp.host}"
            "SMTP_PORT=${toString cfg.smtp.port}"
            "MAILER_FROM=${cfg.smtp.from}"
            # S3
            "S3_ENDPOINT=${cfg.s3.endpoint}"
            "S3_BUCKET=${cfg.s3.bucket}"
            "AWS_REGION=${cfg.s3.region}"
            # Settings
            "LOG_LEVEL=${cfg.settings.logLevel}"
            "PRETTY_BACKTRACE=${lib.boolToString cfg.settings.prettyBacktrace}"
            "NUM_WORKERS=${toString cfg.settings.numWorkers}"
            "POLLING_HISTORICAL_MONTHS=${toString cfg.settings.pollingHistoricalMonths}"
            "OPENAI_MODEL=${cfg.settings.openaiModel}"
            "EVALUATION_MODEL=${cfg.settings.evaluationModel}"
            "AUTH_ALLOWED_EMAIL_DOMAINS=\"${authAllowedRegex}\""
            "FASTEMBED_CACHE_PATH=${cfg.dataDir}/fastembed_cache"
          ];

          # Pass secrets via EnvironmentFile
          EnvironmentFile = [
            (config.my.secrets.getPath "politikerstod" "env")
          ];
        };
      };

      # 3. User & Group
      users.users.politikerstod = {
        isSystemUser = true;
        group = "politikerstod";
        home = cfg.dataDir;
        createHome = true;
      };
      users.groups.politikerstod = {};

      # 4. Persistence / Data Dir Permissions
      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir} 0755 politikerstod politikerstod -"
      ];

      # 5. Firewall - open service port and DB proxy port for remote workers
      networking.firewall.allowedTCPPorts = lib.mkIf (cfg.openFirewall || (cfg.database.enableContainer && cfg.database.allowedHosts != [])) (
        lib.optional cfg.openFirewall cfg.port
        ++ lib.optionals (cfg.database.enableContainer && cfg.database.allowedHosts != []) [5432]
      );

      # 6. Port forwarding for remote database access (when allowedHosts is set)
      # Use socat to forward connections from LAN to the container
      # Binds only to LAN address to avoid conflicts
      systemd.services.politikerstod-db-proxy = lib.mkIf (cfg.database.enableContainer && cfg.database.allowedHosts != []) {
        description = "Forward PostgreSQL connections to politikerstod-db container";
        wantedBy = ["multi-user.target"];
        after = ["network.target" "container@politikerstod-db.service"];
        wants = ["container@politikerstod-db.service"];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:5432,bind=${config.my.listenNetworkAddress},fork,reuseaddr TCP:${cfg.database.container.localAddress}:5432";
          Restart = "always";
          RestartSec = "5";
        };
      };

      containers.politikerstod-db = lib.mkIf cfg.database.enableContainer {
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
            extensions = ps: [ps.pgvector];
            enableTCPIP = true;
            # Listen on all interfaces (internal container IP)
            settings.listen_addresses = lib.mkForce "*";

            # Allow host and remote workers to connect
            authentication = pkgs.lib.mkOverride 10 ''
              # TYPE  DATABASE        USER            ADDRESS                 METHOD
              host    all             all             ${cfg.database.container.hostAddress}/32       trust
              host    all             all             169.254.0.0/16          trust
              ${lib.concatMapStringsSep "\n" (host: "host    all             all             ${host}/32          trust") cfg.database.allowedHosts}
              local   all             all                                     peer
            '';

            ensureDatabases = [cfg.database.name];
            ensureUsers = [
              {
                name = cfg.database.user;
                ensureDBOwnership = false;
              }
            ];

            initialScript = pkgs.writeText "init-politikerstod-db" ''
              CREATE EXTENSION IF NOT EXISTS vector;
              GRANT ALL PRIVILEGES ON DATABASE ${cfg.database.name} TO ${cfg.database.user};
              ALTER DATABASE ${cfg.database.name} OWNER TO ${cfg.database.user};
              GRANT ALL ON SCHEMA public TO ${cfg.database.user};
            '';
          };

          systemd.services.fix-db-permissions = {
            description = "Fix DB permissions for politikerstod";
            after = ["postgresql.service"];
            requires = ["postgresql.service"];
            wantedBy = ["multi-user.target"];
            serviceConfig = {
              Type = "oneshot";
              User = "postgres";
              ExecStart = "${pkgs.postgresql}/bin/psql -d ${cfg.database.name} -c 'CREATE EXTENSION IF NOT EXISTS vector; GRANT ALL ON SCHEMA public TO ${cfg.database.user}'";
            };
          };

          system.stateVersion = "24.05";

          networking.firewall.allowedTCPPorts = [5432];
        };
      };
    };
  };
}
