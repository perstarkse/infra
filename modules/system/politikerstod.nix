{inputs, ...}: {
  config.flake.nixosModules.politikerstod = {
    config,
    lib,
    pkgs,
    mkStandardExposureOptions,
    mkRestrictedPortRules,
    ...
  }: let
    appPkg = inputs.politikerstod.packages.${pkgs.stdenv.hostPlatform.system}.default;

    mkFirewallExtraCommands = port: sources:
      (mkRestrictedPortRules {
        inherit port;
        allowedSources = sources;
      }).iptables;

    enabledInstances = lib.filterAttrs (_: i: i.enable) config.my.politikerstod.instances;

    dbProxyInstances =
      lib.filterAttrs (
        _: i:
          (i.database.enableContainer or false) && (i.database.allowedHosts or []) != []
      )
      enabledInstances;

    containerInstances = lib.filterAttrs (_: i: i.database.enableContainer or false) enabledInstances;

    exposureInstances = lib.filterAttrs (_: i: i.exposure.enable or false) enabledInstances;

    openDbInstances =
      lib.filterAttrs (
        _: i:
          (i.database.enableContainer or false) && (i.database.allowedHosts or []) == []
      )
      enabledInstances;

    mkDbProxyNftRules = lib.concatMapStringsSep "\n" ({value, ...}:
      (mkRestrictedPortRules {
        port = 5432;
        protocol = "tcp";
        allowedSources = value.database.allowedHosts or [];
      }).nft)
    (lib.attrsToList dbProxyInstances);

    mkDbProxyIptablesRules = lib.concatMapStringsSep "\n" ({value, ...}: let
      sources = value.database.allowedHosts or [];
    in ''
      ${lib.concatMapStringsSep "\n" (s: mkFirewallExtraCommands 5432 [s]) sources}
    '') (lib.attrsToList dbProxyInstances);

    mkServiceEnv = name: instance: let
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
      serviceName = "politikerstod-${name}";
      dataDir = instance.dataDir or "/var/lib/${serviceName}";
      inherit (config.my.politikerstod) smtp;
      # With scram (passwordFile set) the DATABASE_URL is built at runtime by
      # the ExecStart wrapper so the password never appears in the store.
      baseEnv = [
        "LOCO_ENV=production"
        "PORT=${toString (instance.port or 5150)}"
        "HOST=${instance.host or "http://localhost:5150"}"
        "CORS_ALLOW_ORIGIN=${instance.host or "http://localhost:5150"}"
        "SMTP_HOST=${smtp.host or "smtp.example.com"}"
        "SMTP_PORT=${toString (smtp.port or 587)}"
        "MAILER_FROM=${smtp.from or "politikerstod@stark.pub"}"
        "S3_ENDPOINT=${instance.s3.endpoint or "http://127.0.0.1:3900"}"
        "S3_BUCKET=${instance.s3.bucket or "politikerstod-${name}"}"
        "AWS_REGION=${instance.s3.region or "garage"}"
        "S3_KEY_PREFIX=${instance.s3.prefix or ""}"
        "LEKEBERG_BASE_URL=${instance.scraper.baseUrl or ""}"
        "LOG_LEVEL=${instance.settings.logLevel or "info"}"
        "PRETTY_BACKTRACE=${lib.boolToString (instance.settings.prettyBacktrace or false)}"
        "NUM_WORKERS=${toString (instance.settings.numWorkers or 2)}"
        "POLLING_HISTORICAL_MONTHS=${toString (instance.settings.pollingHistoricalMonths or 12)}"
        "OPENAI_MODEL=${instance.settings.openaiModel or "gpt-4o-mini"}"
        "EVALUATION_MODEL=${instance.settings.evaluationModel or "gpt-4o-mini"}"
        "AUTH_ALLOWED_EMAIL_DOMAINS=\"${authAllowedRegex}\""
        "FASTEMBED_CACHE_PATH=${dataDir}/fastembed_cache"
      ];
      dbUrl =
        if (instance.database.passwordFile or null) != null
        then []
        else ["DATABASE_URL=postgres://${instance.database.user or "politikerstod"}:@${instance.database.host or "127.0.0.1"}:${toString (instance.database.port or 5432)}/${instance.database.name or "politikerstod"}"];
    in
      baseEnv ++ dbUrl;
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
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = 587;
        };
        secure = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
        from = lib.mkOption {
          type = lib.types.str;
          default = "politikerstod@stark.pub";
        };
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
            startMode = lib.mkOption {
              type = lib.types.enum ["all" "server"];
              default = "all";
            };
            port = lib.mkOption {
              type = lib.types.port;
              default = 5150;
            };
            dataDir = lib.mkOption {
              type = lib.types.path;
              default = "/var/lib/politikerstod-${name}";
            };
            host = lib.mkOption {
              type = lib.types.str;
              default = "http://localhost:5150";
            };
            openFirewall = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
            allowedFirewallSources = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [];
            };
            database = {
              name = lib.mkOption {
                type = lib.types.str;
                default = "politikerstod_${name}";
              };
              user = lib.mkOption {
                type = lib.types.str;
                default = "politikerstod_${name}";
              };
              host = lib.mkOption {
                type = lib.types.str;
                default = "127.0.0.1";
              };
              port = lib.mkOption {
                type = lib.types.port;
                default = 5432;
              };
              enableContainer = lib.mkOption {
                type = lib.types.bool;
                default = false;
              };
              allowedHosts = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [];
              };
              container = {
                name = lib.mkOption {
                  type = lib.types.str;
                  default = "politikerstod-db-${name}";
                };
                hostAddress = lib.mkOption {
                  type = lib.types.str;
                  default = "192.168.100.10";
                };
                localAddress = lib.mkOption {
                  type = lib.types.str;
                  default = "192.168.100.12";
                };
              };
              proxyPort = lib.mkOption {
                type = lib.types.port;
                default = 5432;
                description = "Port for the host-side DB proxy (socat) listener. Must be unique per instance when multiple containers expose port 5432.";
              };
              passwordFile = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Runtime path to a file containing the DB password. When set, container auth switches to scram-sha-256 and DATABASE_URL carries the password.";
              };
            };
            s3 = {
              endpoint = lib.mkOption {
                type = lib.types.str;
                default = "http://127.0.0.1:3900";
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
                description = "Scraper base URL. Must be set per instance.";
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
                  default = null;
                };
              };
            settings = {
              logLevel = lib.mkOption {
                type = lib.types.str;
                default = "info";
              };
              prettyBacktrace = lib.mkOption {
                type = lib.types.bool;
                default = false;
              };
              numWorkers = lib.mkOption {
                type = lib.types.int;
                default = 2;
              };
              pollingHistoricalMonths = lib.mkOption {
                type = lib.types.int;
                default = 12;
              };
              openaiModel = lib.mkOption {
                type = lib.types.str;
                default = "gpt-4o-mini";
              };
              evaluationModel = lib.mkOption {
                type = lib.types.str;
                default = "gpt-4o-mini";
              };
              authAllowedEmailDomains = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = ["*"];
                description = "Allowed email domains for sign-up. Use [\"*\"] to accept all.";
              };
            };
          };
        }));
        default = {};
        description = "Politikerstod service instances. Each instance is an isolated deployment with its own DB, S3 bucket, and scraper source.";
      };
    };

    config = lib.mkIf (enabledInstances != {}) {
      systemd.services = lib.mkMerge [
        (lib.mapAttrs' (
            name: instance: let
              serviceName = "politikerstod-${name}";
              userName = serviceName;
              groupName = serviceName;
              dataDir = instance.dataDir or "/var/lib/${serviceName}";
              secretName = "politikerstod-${name}";
              containerName = instance.database.container.name or "politikerstod-db-${name}";
              hasContainer = instance.database.enableContainer or false;
              passwordFile = instance.database.passwordFile or null;
              startCmd = "${config.my.politikerstod.package}/bin/politikerstod-cli start --${instance.startMode or "all"}";
              execStart =
                if passwordFile != null
                then
                  pkgs.writeShellScript "politikerstod-${name}-start" ''
                    set -euo pipefail
                    export DATABASE_URL="postgres://${instance.database.user or "politikerstod"}:$(cat ${passwordFile})@${instance.database.host or "127.0.0.1"}:${toString (instance.database.port or 5432)}/${instance.database.name or "politikerstod"}"
                    exec ${startCmd}
                  ''
                else startCmd;
            in
              lib.nameValuePair serviceName {
                description = "Politikerstöd Service (${name})";
                wantedBy = ["multi-user.target"];
                after = ["network.target" "garage-provision-${name}.service"] ++ lib.optionals hasContainer ["container@${containerName}.service"];
                wants = lib.optionals hasContainer ["container@${containerName}.service"];
                serviceConfig = {
                  Type = "simple";
                  User = userName;
                  Group = groupName;
                  WorkingDirectory = dataDir;
                  ExecStart = execStart;
                  Restart = "always";
                  RestartSec = "10";
                  Environment = mkServiceEnv name instance;
                  EnvironmentFile = [
                    (config.my.secrets.getPath secretName "env")
                  ];
                };
              }
          )
          enabledInstances)

        (lib.mapAttrs' (
            name: instance: let
              containerName = instance.database.container.name or "politikerstod-db-${name}";
            in
              lib.nameValuePair "politikerstod-${name}-db-proxy" {
                description = "Forward PostgreSQL connections to ${containerName} container";
                wantedBy = ["multi-user.target"];
                after = ["network.target" "container@${containerName}.service"];
                wants = ["container@${containerName}.service"];
                serviceConfig = {
                  Type = "simple";
                  ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:${toString instance.database.proxyPort},bind=${config.my.listenNetworkAddress},fork,reuseaddr TCP:${instance.database.container.localAddress or "192.168.100.12"}:5432";
                  Restart = "always";
                  RestartSec = "5";
                };
              }
          )
          dbProxyInstances)

        (lib.mapAttrs' (
            name: instance: let
              secretName = "politikerstod-${name}";
            in
              lib.nameValuePair "garage-provision-${name}" {
                description = "Provision S3 bucket + key for ${name}";
                wantedBy = ["multi-user.target"];
                after = ["garage.service"];
                before = ["politikerstod-${name}.service"];
                requiredBy = ["politikerstod-${name}.service"];
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                  EnvironmentFile = [
                    (config.my.secrets.getPath secretName "env")
                  ];
                };
                path = [pkgs.garage];
                environment = {
                  GARAGE_RPC_SECRET_FILE = config.my.secrets.getPath "garage" "rpc_secret";
                  GARAGE_ADMIN_ADDR = "127.0.0.1:3903";
                };
                script = ''
                  set -euo pipefail
                  ${pkgs.garage}/bin/garage bucket create ${instance.s3.bucket or "politikerstod-${name}"} >/dev/null 2>&1 || true
                  ${pkgs.garage}/bin/garage key import \
                    --name politikerstod-${name} \
                    --yes \
                    "$AWS_ACCESS_KEY_ID" \
                    "$AWS_SECRET_ACCESS_KEY" \
                    >/dev/null 2>&1 || true
                  # Only grant when garage runs on this host (its config file
                  # exists); in test/worker-only topologies garage is absent
                  # and the app has no S3 access to grant.
                  if [ -f /etc/garage.toml ]; then
                    ${pkgs.garage}/bin/garage bucket allow \
                      --read --write ${instance.s3.bucket or "politikerstod-${name}"} \
                      --key "$AWS_ACCESS_KEY_ID"
                  fi
                '';
              }
          )
          enabledInstances)
      ];

      systemd.tmpfiles.rules =
        lib.mapAttrsToList (
          name: instance: let
            userName = "politikerstod-${name}";
            groupName = userName;
            dataDir = instance.dataDir or "/var/lib/politikerstod-${name}";
          in "d ${dataDir} 0755 ${userName} ${groupName} -"
        )
        enabledInstances;

      users.users =
        lib.mapAttrs' (
          name: instance: let
            userName = "politikerstod-${name}";
            groupName = userName;
            dataDir = instance.dataDir or "/var/lib/politikerstod-${name}";
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
            lib.nameValuePair "politikerstod-${name}" {}
        )
        enabledInstances;

      my.exposure.services =
        lib.mapAttrs' (
          name: instance: let
            serviceName = "politikerstod-${name}";
          in
            lib.nameValuePair serviceName {
              upstream = {
                host = config.my.listenNetworkAddress or "0.0.0.0";
                port = instance.port or 5150;
              };
              router = {
                enable = instance.exposure.router.enable or false;
                targets = instance.exposure.router.targets or [];
              };
              http.virtualHosts = lib.optional ((instance.exposure.domain or null) != null) {
                inherit (instance.exposure) domain;
                public = instance.exposure.public or false;
                cloudflareProxied = instance.exposure.cloudflareProxied or false;
                websockets = false;
              };
              firewall.local = {
                enable = (instance.openFirewall or true) || (instance.allowedFirewallSources or []) != [];
                tcp = [(instance.port or 5150)];
                allowedSources = instance.allowedFirewallSources or [];
              };
            }
        )
        exposureInstances;

      networking.firewall = {
        allowedTCPPorts = lib.optionals (openDbInstances != {}) [5432];
        extraInputRules = lib.mkIf (dbProxyInstances != {}) (lib.mkAfter mkDbProxyNftRules);
        extraCommands = lib.mkIf (!config.networking.nftables.enable && dbProxyInstances != {}) (lib.mkAfter mkDbProxyIptablesRules);
      };

      containers =
        lib.mapAttrs' (
          name: instance: let
            containerName = instance.database.container.name or "politikerstod-db-${name}";
            hostStateVersion = config.my.stateVersion;
            passwordFile = instance.database.passwordFile or null;
            dbUser = instance.database.user or "politikerstod";
            dbName = instance.database.name or "politikerstod";
            hostAddress = instance.database.container.hostAddress or "192.168.100.10";
            allowedHosts = instance.database.allowedHosts or [];
            authMethod =
              if passwordFile != null
              then "scram-sha-256"
              else "trust";
          in
            lib.nameValuePair containerName {
              autoStart = true;
              privateNetwork = true;
              inherit hostAddress;
              localAddress = instance.database.container.localAddress or "192.168.100.12";
              bindMounts = lib.optionalAttrs (passwordFile != null) {
                "/run/secrets/db-password" = {
                  hostPath = passwordFile;
                  isReadOnly = true;
                };
              };

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
                    host    all             all             ${hostAddress}/32       ${authMethod}
                    host    all             all             169.254.0.0/16          ${authMethod}
                    ${lib.concatMapStringsSep "\n" (host: "host    all             all             ${host}/32          ${authMethod}") allowedHosts}
                    local   all             all                                     peer
                  '';
                  ensureDatabases = [dbName];
                  ensureUsers = [
                    {
                      name = dbUser;
                      # NixOS 25.05+ renamed ensureClause (string) to
                      # ensureClauses (attrset of bool). Re-encode "LOGIN" as
                      # the corresponding clause flag.
                      ensureClauses.LOGIN = true;
                    }
                  ];
                  initialScript = pkgs.writeText "init-${containerName}" ''
                    -- Install vector in template1 so all new databases inherit it
                    \c template1
                    CREATE EXTENSION IF NOT EXISTS vector;
                  '';
                };

                systemd.services.fix-db-password = lib.mkIf (passwordFile != null) {
                  description = "Set DB password for ${name} (scram)";
                  after = ["postgresql.service" "postgresql-setup.service"];
                  requires = ["postgresql.service"];
                  wantedBy = ["multi-user.target"];
                  serviceConfig = {
                    Type = "oneshot";
                    # root reads the 0400 secret; psql runs as postgres via
                    # runuser so the peer-auth local line still applies.
                  };
                  script = ''
                    pass=$(cat /run/secrets/db-password)
                    printf "ALTER USER ${dbUser} WITH PASSWORD '%s';\n" "$pass" | \
                      ${pkgs.util-linux}/bin/runuser -u postgres -- ${pkgs.postgresql}/bin/psql -d postgres
                  '';
                };

                systemd.services.fix-db-permissions = {
                  description = "Fix DB permissions for ${name}";
                  after = ["postgresql.service" "postgresql-setup.service"];
                  requires = ["postgresql.service" "postgresql-setup.service"];
                  wantedBy = ["multi-user.target"];
                  serviceConfig = {
                    Type = "oneshot";
                    User = "postgres";
                  };
                  script = ''
                    ${pkgs.postgresql}/bin/psql -d ${dbName} <<'SQL'
                    CREATE EXTENSION IF NOT EXISTS vector;
                    GRANT ALL ON SCHEMA public TO ${dbUser};
                    SQL
                    ${pkgs.postgresql}/bin/psql -d postgres -c "ALTER DATABASE ${dbName} OWNER TO ${dbUser}"
                    ${pkgs.postgresql}/bin/psql -d postgres -c "GRANT ALL PRIVILEGES ON DATABASE ${dbName} TO ${dbUser}"
                    ${pkgs.postgresql}/bin/psql -d ${dbName} <<'SQL'
                    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${dbUser};
                    GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${dbUser};
                    SQL
                    ${pkgs.postgresql}/bin/psql -d ${dbName} -c \
                      "SELECT format('ALTER TABLE public.%I OWNER TO ${dbUser};', tablename) FROM pg_tables WHERE schemaname = 'public'" \
                      | ${pkgs.postgresql}/bin/psql -d ${dbName}
                    ${pkgs.postgresql}/bin/psql -d ${dbName} -c \
                      "SELECT format('ALTER SEQUENCE public.%I OWNER TO ${dbUser};', sequencename) FROM pg_sequences WHERE schemaname = 'public'" \
                      | ${pkgs.postgresql}/bin/psql -d ${dbName}
                  '';
                };

                system.stateVersion = hostStateVersion;
                networking.firewall.allowedTCPPorts = [5432];
              };
            }
        )
        containerInstances;
    };
  };
}
