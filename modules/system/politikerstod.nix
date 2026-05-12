{inputs, ...}: {
  config.flake.nixosModules.politikerstod = {
    config,
    lib,
    pkgs,
    mkStandardExposureOptions,
    ...
  }: let
    cfg = config.my.politikerstod;
    appPkg = inputs.politikerstod.packages.${pkgs.stdenv.hostPlatform.system}.default;

    mkFirewallExtraCommands = port: sources: let
      allowRules = map (
        source:
          if builtins.match ".*:.*" source != null
          then "${pkgs.iptables}/bin/ip6tables -A nixos-fw -p tcp -s ${source} --dport ${toString port} -j ACCEPT"
          else "${pkgs.iptables}/bin/iptables -A nixos-fw -p tcp -s ${source} --dport ${toString port} -j ACCEPT"
      ) sources;
    in
      lib.concatStringsSep "\n" (
        allowRules
        ++ [
          "${pkgs.iptables}/bin/iptables -A nixos-fw -p tcp --dport ${toString port} -j DROP"
          "${pkgs.iptables}/bin/ip6tables -A nixos-fw -p tcp --dport ${toString port} -j DROP"
        ]
      );

    mkInstanceConfig = name: instance: let
      escapeForSystemd = s: builtins.replaceStrings ["\\" "$" "\""] ["\\\\" "$$" "\\\""] s;
      authAllowedRegex = "(?i)(" + (builtins.concatStringsSep "|" (
        map (d: "@" + (escapeForSystemd (lib.strings.escapeRegex d)) + "$$") instance.settings.authAllowedEmailDomains
      )) + ")";

      serviceName = "politikerstod-${name}";
      containerName = instance.database.container.name;
      userName = "politikerstod-${name}";
      groupName = "politikerstod-${name}";
      secretName = "politikerstod-${name}";
      dataDir = instance.dataDir;

      dbProxyFirewallSourceRules = lib.concatMapStringsSep "\n" (source:
        if builtins.match ".*:.*" source != null
        then "ip6 saddr ${source} tcp dport 5432 accept"
        else "ip saddr ${source} tcp dport 5432 accept"
      ) instance.database.allowedHosts;
    in {
      systemd = {
        services."${serviceName}" = {
          description = "Politikerstöd Service (${name})";
          wantedBy = ["multi-user.target"];
          after = ["network.target"];
          serviceConfig = {
            Type = "simple";
            User = userName;
            Group = groupName;
            WorkingDirectory = dataDir;
            ExecStart = "${cfg.package}/bin/politikerstod-cli start --${instance.startMode}";
            Restart = "always";
            RestartSec = "10";
            Environment = [
              "LOCO_ENV=production"
              "PORT=${toString instance.port}"
              "HOST=${instance.host}"
              "CORS_ALLOW_ORIGIN=${instance.host}"
              "DATABASE_URL=postgres://${instance.database.user}@${instance.database.host}:${toString instance.database.port}/${instance.database.name}"
              "SMTP_HOST=${cfg.smtp.host}"
              "SMTP_PORT=${toString cfg.smtp.port}"
              "MAILER_FROM=${cfg.smtp.from}"
              "S3_ENDPOINT=${instance.s3.endpoint}"
              "S3_BUCKET=${instance.s3.bucket}"
              "AWS_REGION=${instance.s3.region}"
              "S3_KEY_PREFIX=${instance.s3.prefix}"
              "LEKEBERG_BASE_URL=${instance.scraper.baseUrl}"
              "LOG_LEVEL=${instance.settings.logLevel}"
              "PRETTY_BACKTRACE=${lib.boolToString instance.settings.prettyBacktrace}"
              "NUM_WORKERS=${toString instance.settings.numWorkers}"
              "POLLING_HISTORICAL_MONTHS=${toString instance.settings.pollingHistoricalMonths}"
              "OPENAI_MODEL=${instance.settings.openaiModel}"
              "EVALUATION_MODEL=${instance.settings.evaluationModel}"
              "AUTH_ALLOWED_EMAIL_DOMAINS=\"${authAllowedRegex}\""
              "FASTEMBED_CACHE_PATH=${dataDir}/fastembed_cache"
            ];
            EnvironmentFile = [
              (config.my.secrets.getPath secretName "env")
            ];
          };
        };

        tmpfiles.rules = [
          "d ${dataDir} 0755 ${userName} ${groupName} -"
        ];

        services."${serviceName}-db-proxy" = lib.mkIf (instance.database.enableContainer && instance.database.allowedHosts != []) {
          description = "Forward PostgreSQL connections to ${containerName} container";
          wantedBy = ["multi-user.target"];
          after = ["network.target" "container@${containerName}.service"];
          wants = ["container@${containerName}.service"];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:5432,bind=${config.my.listenNetworkAddress},fork,reuseaddr TCP:${instance.database.container.localAddress}:5432";
            Restart = "always";
            RestartSec = "5";
          };
        };
      };

      users.users."${userName}" = {
        isSystemUser = true;
        group = groupName;
        home = dataDir;
        createHome = true;
      };
      users.groups."${groupName}" = {};

      my.exposure.services."${serviceName}" = lib.mkIf instance.exposure.enable {
        upstream = {
          host = config.my.listenNetworkAddress or "0.0.0.0";
          inherit (instance) port;
        };
        router = {inherit (instance.exposure.router) enable targets;};
        http.virtualHosts = lib.optional (instance.exposure.domain != null) {
          inherit (instance.exposure) domain;
          inherit (instance.exposure) public cloudflareProxied;
          websockets = false;
        };
        firewall.local = {
          enable = instance.openFirewall || instance.allowedFirewallSources != [];
          tcp = [instance.port];
          allowedSources = instance.allowedFirewallSources;
        };
      };

      networking.firewall = {
        allowedTCPPorts =
          lib.optionals (instance.database.enableContainer && instance.database.allowedHosts == []) [5432];

        extraInputRules = lib.mkMerge [
          (lib.mkIf (instance.database.enableContainer && instance.database.allowedHosts != []) (lib.mkAfter ''
            ${dbProxyFirewallSourceRules}
            tcp dport 5432 drop
          ''))
        ];

        extraCommands = lib.mkMerge [
          (lib.mkIf (!config.networking.nftables.enable && instance.database.enableContainer && instance.database.allowedHosts != []) (lib.mkAfter ''
            ${mkFirewallExtraCommands 5432 instance.database.allowedHosts}
          ''))
        ];
      };

      containers."${containerName}" = lib.mkIf instance.database.enableContainer {
        autoStart = true;
        privateNetwork = true;
        inherit (instance.database.container) hostAddress;
        inherit (instance.database.container) localAddress;

        config = {
          pkgs,
          lib,
          ...
        }: {
          services.postgresql = {
            enable = true;
            extensions = ps: [ps.pgvector];
            enableTCPIP = true;
            settings.listen_addresses = lib.mkForce "*";
            authentication = pkgs.lib.mkOverride 10 ''
              host    all             all             ${instance.database.container.hostAddress}/32       trust
              host    all             all             169.254.0.0/16          trust
              ${lib.concatMapStringsSep "\n" (host: "host    all             all             ${host}/32          trust") instance.database.allowedHosts}
              local   all             all                                     peer
            '';
            ensureDatabases = [instance.database.name];
            ensureUsers = [
              {
                name = instance.database.user;
                ensureDBOwnership = false;
              }
            ];
            initialScript = pkgs.writeText "init-${containerName}" ''
              CREATE EXTENSION IF NOT EXISTS vector;
              GRANT ALL PRIVILEGES ON DATABASE ${instance.database.name} TO ${instance.database.user};
              ALTER DATABASE ${instance.database.name} OWNER TO ${instance.database.user};
              GRANT ALL ON SCHEMA public TO ${instance.database.user};
            '';
          };

          systemd.services.fix-db-permissions = {
            description = "Fix DB permissions for ${name}";
            after = ["postgresql.service"];
            requires = ["postgresql.service"];
            wantedBy = ["multi-user.target"];
            serviceConfig = {
              Type = "oneshot";
              User = "postgres";
              ExecStart = "${pkgs.postgresql}/bin/psql -d ${instance.database.name} -c 'CREATE EXTENSION IF NOT EXISTS vector; GRANT ALL ON SCHEMA public TO ${instance.database.user}'";
            };
          };

          system.stateVersion = "24.05";
          networking.firewall.allowedTCPPorts = [5432];
        };
      };
    };

    enabledInstances = lib.filterAttrs (_: instance: instance.enable) cfg.instances;
  in {
    options.my.politikerstod = {
      package = lib.mkOption {
        type = lib.types.package;
        default = appPkg;
        defaultText = lib.literalExpression "inputs.politikerstod.packages.${pkgs.stdenv.hostPlatform.system}.default";
        description = "Package providing the politikerstod-cli binary.";
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
          default = false;
          description = "Use secure connection (TLS)";
        };
        from = lib.mkOption {
          type = lib.types.str;
          default = "politikerstod@stark.pub";
          description = "Email sender address";
        };
      };

      instances = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule ({name, config, ...}: {
          options = {
            enable = lib.mkEnableOption "Politikerstöd instance ${name}";

            package = lib.mkOption {
              type = lib.types.package;
              default = cfg.package;
              defaultText = lib.literalExpression "config.my.politikerstod.package";
              description = "Package override for this instance.";
            };

            startMode = lib.mkOption {
              type = lib.types.enum ["all" "server"];
              default = "all";
              description = "Whether to run server+workers or server-only.";
            };

            port = lib.mkOption {
              type = lib.types.port;
              default = 5150;
              description = "Port to listen on";
            };

            dataDir = lib.mkOption {
              type = lib.types.path;
              default = "/var/lib/politikerstod-${name}";
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

            allowedFirewallSources = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [];
              example = ["10.0.0.1"];
              description = "Source IPs/CIDRs allowed to access the service port.";
            };

            database = {
              name = lib.mkOption {
                type = lib.types.str;
                default = "politikerstod_${name}";
                description = "Database name";
              };
              user = lib.mkOption {
                type = lib.types.str;
                default = "politikerstod_${name}";
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
                example = ["10.0.0.15"];
                description = "Additional hosts allowed to connect to the database.";
              };
              container = {
                name = lib.mkOption {
                  type = lib.types.str;
                  default = "politikerstod-db-${name}";
                  description = "NixOS container name. Set to old name ('politikerstod-db') to preserve existing data during migration.";
                };
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
              prefix = lib.mkOption {
                type = lib.types.str;
                description = "S3 key prefix (maps to S3_KEY_PREFIX env var). Must be set per instance.";
              };
            };

            scraper = {
              baseUrl = lib.mkOption {
                type = lib.types.str;
                description = "Base URL for the meeting scraper (maps to LEKEBERG_BASE_URL env var). Must be set per instance.";
              };
            };

            exposure =
              mkStandardExposureOptions {
                subject = "Politikerstöd (${name})";
                visibility = "public";
                withRouter = true;
              }
              // {
                domain = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = lib.removePrefix "https://" (lib.removePrefix "http://" config.host);
                  description = "Domain for the service vhost.";
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
        }));
        default = {};
        description = "Politikerstod service instances. Each instance is an isolated deployment with its own DB, S3 prefix, and scraper source.";
      };
    };

    config = lib.mkMerge (lib.mapAttrsToList mkInstanceConfig enabledInstances);
  };
}
