{inputs, ...}: {
  config.flake.nixosModules.politikerstod = {
    config,
    lib,
    pkgs,
    mkStandardExposureOptions,
    ...
  }: let
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

    mkInstanceConfig = name: let
      i = config.my.politikerstod.instances.${name} or {};
      enabled = i.enable or false;
      escapeForSystemd = s: builtins.replaceStrings ["\\" "$" "\""] ["\\\\" "$$" "\\\""] s;
      authAllowedRegex = "(?i)(" + (builtins.concatStringsSep "|" (
        map (d: "@" + (escapeForSystemd (lib.strings.escapeRegex d)) + "$$") (i.settings.authAllowedEmailDomains or [])
      )) + ")";

      serviceName = "politikerstod-${name}";
      containerName = i.database.container.name or "politikerstod-db-${name}";
      userName = "politikerstod-${name}";
      groupName = "politikerstod-${name}";
      secretName = "politikerstod-${name}";
      dataDir = i.dataDir or "/var/lib/politikerstod-${name}";

      dbProxyFirewallSourceRules = lib.concatMapStringsSep "\n" (source:
        if builtins.match ".*:.*" source != null
        then "ip6 saddr ${source} tcp dport 5432 accept"
        else "ip saddr ${source} tcp dport 5432 accept"
      ) (i.database.allowedHosts or []);
    in
      lib.mkIf enabled {
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
              ExecStart = "${config.my.politikerstod.package}/bin/politikerstod-cli start --${i.startMode or "all"}";
              Restart = "always";
              RestartSec = "10";
              Environment = [
                "LOCO_ENV=production"
                "PORT=${toString (i.port or 5150)}"
                "HOST=${i.host or "http://localhost:5150"}"
                "CORS_ALLOW_ORIGIN=${i.host or "http://localhost:5150"}"
                "DATABASE_URL=postgres://${i.database.user or "politikerstod"}:@${i.database.host or "127.0.0.1"}:${toString (i.database.port or 5432)}/${i.database.name or "politikerstod"}"
                "SMTP_HOST=${config.my.politikerstod.smtp.host or "smtp.example.com"}"
                "SMTP_PORT=${toString (config.my.politikerstod.smtp.port or 587)}"
                "MAILER_FROM=${config.my.politikerstod.smtp.from or "politikerstod@stark.pub"}"
                "S3_ENDPOINT=${i.s3.endpoint or "http://127.0.0.1:3900"}"
                "S3_BUCKET=${i.s3.bucket or "politikerstod"}"
                "AWS_REGION=${i.s3.region or "garage"}"
                "S3_KEY_PREFIX=${i.s3.prefix or ""}"
                "LEKEBERG_BASE_URL=${i.scraper.baseUrl or ""}"
                "LOG_LEVEL=${i.settings.logLevel or "info"}"
                "PRETTY_BACKTRACE=${lib.boolToString (i.settings.prettyBacktrace or false)}"
                "NUM_WORKERS=${toString (i.settings.numWorkers or 2)}"
                "POLLING_HISTORICAL_MONTHS=${toString (i.settings.pollingHistoricalMonths or 12)}"
                "OPENAI_MODEL=${i.settings.openaiModel or "gpt-4o-mini"}"
                "EVALUATION_MODEL=${i.settings.evaluationModel or "gpt-4o-mini"}"
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

          services."${serviceName}-db-proxy" = lib.mkIf (
            (i.database.enableContainer or false) && (i.database.allowedHosts or []) != []
          ) {
            description = "Forward PostgreSQL connections to ${containerName} container";
            wantedBy = ["multi-user.target"];
            after = ["network.target" "container@${containerName}.service"];
            wants = ["container@${containerName}.service"];
            serviceConfig = {
              Type = "simple";
              ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:5432,bind=${config.my.listenNetworkAddress},fork,reuseaddr TCP:${i.database.container.localAddress or "192.168.100.12"}:5432";
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

        my.exposure.services."${serviceName}" = lib.mkIf (i.exposure.enable or false) {
          upstream = {
            host = config.my.listenNetworkAddress or "0.0.0.0";
            port = i.port or 5150;
          };
          router = {
            enable = i.exposure.router.enable or false;
            targets = i.exposure.router.targets or [];
          };
          http.virtualHosts = lib.optional ((i.exposure.domain or null) != null) {
            domain = i.exposure.domain;
            public = i.exposure.public or false;
            cloudflareProxied = i.exposure.cloudflareProxied or false;
            websockets = false;
          };
          firewall.local = {
            enable = (i.openFirewall or true) || (i.allowedFirewallSources or []) != [];
            tcp = [ (i.port or 5150) ];
            allowedSources = i.allowedFirewallSources or [];
          };
        };

        networking.firewall = {
          allowedTCPPorts =
            lib.optionals ((i.database.enableContainer or false) && (i.database.allowedHosts or []) == []) [5432];

          extraInputRules = lib.mkMerge [
            (lib.mkIf ((i.database.enableContainer or false) && (i.database.allowedHosts or []) != []) (lib.mkAfter ''
              ${dbProxyFirewallSourceRules}
              tcp dport 5432 drop
            ''))
          ];

          extraCommands = lib.mkMerge [
            (lib.mkIf (!config.networking.nftables.enable && (i.database.enableContainer or false) && (i.database.allowedHosts or []) != []) (lib.mkAfter ''
              ${mkFirewallExtraCommands 5432 (i.database.allowedHosts or [])}
            ''))
          ];
        };

        containers."${containerName}" = lib.mkIf (i.database.enableContainer or false) {
          autoStart = true;
          privateNetwork = true;
          hostAddress = i.database.container.hostAddress or "192.168.100.10";
          localAddress = i.database.container.localAddress or "192.168.100.12";

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
                host    all             all             ${i.database.container.hostAddress or "192.168.100.10"}/32       trust
                host    all             all             169.254.0.0/16          trust
                ${lib.concatMapStringsSep "\n" (host: "host    all             all             ${host}/32          trust") (i.database.allowedHosts or [])}
                local   all             all                                     peer
              '';
              ensureDatabases = [ (i.database.name or "politikerstod") ];
              ensureUsers = [
                {
                  name = i.database.user or "politikerstod";
                  ensureDBOwnership = false;
                }
              ];
              initialScript = pkgs.writeText "init-${containerName}" ''
                CREATE EXTENSION IF NOT EXISTS vector;
                GRANT ALL PRIVILEGES ON DATABASE ${i.database.name or "politikerstod"} TO ${i.database.user or "politikerstod"};
                ALTER DATABASE ${i.database.name or "politikerstod"} OWNER TO ${i.database.user or "politikerstod"};
                GRANT ALL ON SCHEMA public TO ${i.database.user or "politikerstod"};
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
                ExecStart = "${pkgs.postgresql}/bin/psql -d ${i.database.name or "politikerstod"} -c 'CREATE EXTENSION IF NOT EXISTS vector; GRANT ALL ON SCHEMA public TO ${i.database.user or "politikerstod"}'";
              };
            };

            system.stateVersion = "24.05";
            networking.firewall.allowedTCPPorts = [5432];
          };
        };
      };
  in {
    options.my.politikerstod = {
      package = lib.mkOption {
        type = lib.types.package;
        default = appPkg;
        defaultText = lib.literalExpression "inputs.politikerstod.packages.${pkgs.stdenv.hostPlatform.system}.default";
        description = "Package providing the politikerstod-cli binary.";
      };

      smtp = {
        host = lib.mkOption { type = lib.types.str; default = "smtp.example.com"; };
        port = lib.mkOption { type = lib.types.port; default = 587; };
        secure = lib.mkOption { type = lib.types.bool; default = false; };
        from = lib.mkOption { type = lib.types.str; default = "politikerstod@stark.pub"; };
      };

      instances = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
          options = {
            enable = lib.mkEnableOption "Politikerstöd instance ${name}";
            package = lib.mkOption {
              type = lib.types.package;
              default = config.my.politikerstod.package;
              defaultText = lib.literalExpression "config.my.politikerstod.package";
            };
            startMode = lib.mkOption { type = lib.types.enum ["all" "server"]; default = "all"; };
            port = lib.mkOption { type = lib.types.port; default = 5150; };
            dataDir = lib.mkOption { type = lib.types.path; default = "/var/lib/politikerstod-${name}"; };
            host = lib.mkOption { type = lib.types.str; default = "http://localhost:5150"; };
            openFirewall = lib.mkOption { type = lib.types.bool; default = true; };
            allowedFirewallSources = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
            database = {
              name = lib.mkOption { type = lib.types.str; default = "politikerstod_${name}"; };
              user = lib.mkOption { type = lib.types.str; default = "politikerstod_${name}"; };
              host = lib.mkOption { type = lib.types.str; default = "127.0.0.1"; };
              port = lib.mkOption { type = lib.types.port; default = 5432; };
              enableContainer = lib.mkOption { type = lib.types.bool; default = false; };
              allowedHosts = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
              container = {
                name = lib.mkOption {
                  type = lib.types.str;
                  default = "politikerstod-db-${name}";
                };
                hostAddress = lib.mkOption { type = lib.types.str; default = "192.168.100.10"; };
                localAddress = lib.mkOption { type = lib.types.str; default = "192.168.100.12"; };
              };
            };
            s3 = {
              endpoint = lib.mkOption { type = lib.types.str; default = "http://127.0.0.1:3900"; };
              bucket = lib.mkOption { type = lib.types.str; default = "politikerstod"; };
              region = lib.mkOption { type = lib.types.str; default = "garage"; };
              prefix = lib.mkOption {
                type = lib.types.str;
                description = "S3 key prefix. Must be set per instance.";
              };
            };
            scraper = {
              baseUrl = lib.mkOption {
                type = lib.types.str;
                description = "Scraper base URL. Must be set per instance.";
              };
            };
            exposure = mkStandardExposureOptions {
              subject = "Politikerstöd (${name})";
              visibility = "public";
              withRouter = true;
            } // {
              domain = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
            };
            settings = {
              logLevel = lib.mkOption { type = lib.types.str; default = "info"; };
              prettyBacktrace = lib.mkOption { type = lib.types.bool; default = false; };
              numWorkers = lib.mkOption { type = lib.types.int; default = 2; };
              pollingHistoricalMonths = lib.mkOption { type = lib.types.int; default = 12; };
              openaiModel = lib.mkOption { type = lib.types.str; default = "gpt-4o-mini"; };
              evaluationModel = lib.mkOption { type = lib.types.str; default = "gpt-4o-mini"; };
              authAllowedEmailDomains = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = ["gmail.com" "hotmail.com" "lekeberg.se" "stark.pub"];
              };
            };
          };
        }));
        default = {};
        description = "Politikerstod service instances. Each instance is an isolated deployment with its own DB, S3 prefix, and scraper source.";
      };
    };

    # Config generated explicitly per known instance name.
    # mkInstanceConfig uses lazy mkIf on config.my.politikerstod.instances.<name>.enable,
    # so disabled instances produce no config. Add new instance names here when needed.
    config = lib.mkMerge [
      (mkInstanceConfig "lekeberg")
      (mkInstanceConfig "orebro")
    ];
  };
}
