_: {
  config.flake.nixosModules.supabase = {
    config,
    lib,
    pkgs,
    mkStandardExposureOptions,
    ...
  }: let
    cfg = config.my.supabase;

    # Pinned upstream self-hosting stack (supabase/supabase docker/ dir).
    # Bump rev + hash together. Image tags are pinned inside the compose file.
    supabaseSrc = pkgs.fetchFromGitHub {
      owner = "supabase";
      repo = "supabase";
      inherit (cfg) rev;
      inherit (cfg) hash;
    };
    stackSrc = "${supabaseSrc}/docker";

    # Additive overlay only — never edit upstream compose.
    # - Drop Kong HTTPS (TLS terminates at io)
    # - Bind Supavisor to loopback (do not LAN-publish Postgres)
    # - Point storage-api at Garage S3 (container-reachable host address)
    garageOverlay = pkgs.writeText "docker-compose.garage.yml" ''
      services:
        kong:
          ports: !override
            - "''${KONG_HTTP_PORT}:8000/tcp"
        supavisor:
          ports: !override
            - "127.0.0.1:${toString cfg.postgresPort}:5432"
            - "127.0.0.1:''${POOLER_PROXY_PORT_TRANSACTION}:6543"
        storage:
          environment:
            STORAGE_BACKEND: s3
            GLOBAL_S3_BUCKET: ${cfg.storage.bucket}
            GLOBAL_S3_ENDPOINT: ${cfg.storage.endpoint}
            GLOBAL_S3_PROTOCOL: http
            GLOBAL_S3_FORCE_PATH_STYLE: "true"
            AWS_ACCESS_KEY_ID: ''${AWS_ACCESS_KEY_ID}
            AWS_SECRET_ACCESS_KEY: ''${AWS_SECRET_ACCESS_KEY}
            REGION: ${cfg.storage.region}
    '';

    secretsEnv = config.my.secrets.getPath "supabase" "env";
    garageS3AccessKey = config.my.secrets.getPath "garage-s3" "access_key_id";
    garageS3SecretKey = config.my.secrets.getPath "garage-s3" "secret_access_key";
    stackDir = "${cfg.dataDir}/stack";
    envPath = "${stackDir}/.env";
  in {
    options.my.supabase = {
      enable = lib.mkEnableOption "Self-hosted Supabase Docker Compose stack";

      rev = lib.mkOption {
        type = lib.types.str;
        default = "9cf6ae1f6779efcef70dcc94d64e5d8e1cee8304";
        description = "Pinned supabase/supabase commit (docker/ directory).";
      };

      hash = lib.mkOption {
        type = lib.types.str;
        default = "sha256-sbumDpJCBDlcFyj2KwKeqJ/S9mrdotITgqqtOf+z45A=";
        description = "fetchFromGitHub hash for cfg.rev.";
      };

      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/supabase";
        description = "Persistent state (compose project + postgres data + dumps).";
      };

      postgresPort = lib.mkOption {
        type = lib.types.port;
        default = 54322;
        description = "Host port bound on 127.0.0.1 for Supavisor/Postgres (prevents collision with native postgresql on 5432).";
      };

      kongPort = lib.mkOption {
        type = lib.types.port;
        default = 8000;
        description = "Host port published for Kong HTTP (upstream of io nginx).";
      };

      siteUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://accounting.lan.stark.pub";
        description = "GoTrue SITE_URL (Accounted public origin).";
      };

      additionalRedirectUrls = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "https://accounting.lan.stark.pub/auth/callback"
          "https://accounting.lan.stark.pub/api/auth/callback"
        ];
        description = "GoTrue ADDITIONAL_REDIRECT_URLS allowlist.";
      };

      dashboardUsername = lib.mkOption {
        type = lib.types.str;
        default = "supabase";
        description = "Studio / Kong dashboard basic-auth username.";
      };

      poolerTenantId = lib.mkOption {
        type = lib.types.str;
        default = "makemake";
        description = "Supavisor tenant identifier.";
      };

      smtp = {
        host = lib.mkOption {
          type = lib.types.str;
          default = "mail-eu.smtp2go.com";
          description = "SMTP host for GoTrue auth emails.";
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = 587;
          description = "SMTP port (587 STARTTLS).";
        };
        adminEmail = lib.mkOption {
          type = lib.types.str;
          default = "noreply@stark.pub";
          description = "SMTP_ADMIN_EMAIL / From address.";
        };
        senderName = lib.mkOption {
          type = lib.types.str;
          default = "Accounted";
          description = "SMTP_SENDER_NAME.";
        };
      };

      storage = {
        bucket = lib.mkOption {
          type = lib.types.str;
          default = "supabase";
          description = "Garage bucket used as GLOBAL_S3_BUCKET.";
        };
        endpoint = lib.mkOption {
          type = lib.types.str;
          # Host LAN IP so containers reach Garage (binds [::]:3900).
          default = "http://10.0.0.10:3900";
          description = "S3 endpoint reachable from Docker containers.";
        };
        region = lib.mkOption {
          type = lib.types.str;
          default = "garage";
          description = "S3 region string.";
        };
        provision = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Create Garage bucket + import storage key when local Garage is enabled.";
        };
      };

      backup = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Logical pg_dump via my.backups.supabase (garage-s3 + b2).";
        };
      };

      disableSignup = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "GoTrue DISABLE_SIGNUP.";
      };

      exposure = mkStandardExposureOptions {
        subject = "Supabase (Kong)";
        visibility = "internal";
        withRouter = true;
        withExtraConfigDefault = ''
          client_max_body_size 60M;
          proxy_read_timeout 3600;
          proxy_send_timeout 3600;
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = config.virtualisation.docker.enable;
          message = "my.supabase requires virtualisation.docker (enable my.docker).";
        }
        {
          assertion = cfg.exposure.enable -> cfg.exposure.domain != null;
          message = "my.supabase.exposure.domain must be set when exposure is enabled.";
        }
      ];

      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir} 0750 root root -"
        "d ${cfg.dataDir}/backups 0750 root root -"
        "d ${stackDir} 0750 root root -"
      ];

      # Render compose .env from Clan secrets + module config (no secrets in the store).
      systemd.services.supabase-env-render = {
        description = "Render Supabase Docker Compose .env from Clan secrets";
        wantedBy = ["multi-user.target"];
        before = ["supabase-stack.service"];
        after = ["network.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          EnvironmentFile = [secretsEnv];
        };
        script = let
          publicUrl =
            if cfg.exposure.domain != null
            then "https://${cfg.exposure.domain}"
            else "http://127.0.0.1:${toString cfg.kongPort}";
          redirectUrls = lib.concatStringsSep "," cfg.additionalRedirectUrls;
        in ''
          set -euo pipefail
          umask 077
          mkdir -p ${lib.escapeShellArg stackDir}
          AWS_ID="''${AWS_ACCESS_KEY_ID:-}"
          AWS_SECRET="''${AWS_SECRET_ACCESS_KEY:-}"
          if ! echo "$AWS_ID" | ${pkgs.gnugrep}/bin/grep -E '^GK[0-9a-fA-F]{24}$' >/dev/null 2>&1; then
            if [ -r "${garageS3AccessKey}" ] && [ -r "${garageS3SecretKey}" ]; then
              AWS_ID="$(tr -d '\n' < "${garageS3AccessKey}")"
              AWS_SECRET="$(tr -d '\n' < "${garageS3SecretKey}")"
            fi
          fi
          {
            echo "# Generated by supabase-env-render.service — do not edit."
            echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD"
            echo "JWT_SECRET=$JWT_SECRET"
            echo "ANON_KEY=$ANON_KEY"
            echo "SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY"
            echo "SECRET_KEY_BASE=$SECRET_KEY_BASE"
            echo "REALTIME_DB_ENC_KEY=$REALTIME_DB_ENC_KEY"
            echo "VAULT_ENC_KEY=$VAULT_ENC_KEY"
            echo "PG_META_CRYPTO_KEY=$PG_META_CRYPTO_KEY"
            echo "LOGFLARE_PUBLIC_ACCESS_TOKEN=$LOGFLARE_PUBLIC_ACCESS_TOKEN"
            echo "LOGFLARE_PRIVATE_ACCESS_TOKEN=$LOGFLARE_PRIVATE_ACCESS_TOKEN"
            echo "S3_PROTOCOL_ACCESS_KEY_ID=$S3_PROTOCOL_ACCESS_KEY_ID"
            echo "S3_PROTOCOL_ACCESS_KEY_SECRET=$S3_PROTOCOL_ACCESS_KEY_SECRET"
            echo "DASHBOARD_USERNAME=${cfg.dashboardUsername}"
            echo "DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD"
            echo "AWS_ACCESS_KEY_ID=$AWS_ID"
            echo "AWS_SECRET_ACCESS_KEY=$AWS_SECRET"
            echo "SMTP_USER=$SMTP_USER"
            echo "SMTP_PASS=$SMTP_PASS"
            echo "POSTGRES_HOST=db"
            echo "POSTGRES_DB=postgres"
            echo "POSTGRES_PORT=${toString cfg.postgresPort}"
            echo "POOLER_PROXY_PORT_TRANSACTION=6543"
            echo "POOLER_DEFAULT_POOL_SIZE=20"
            echo "POOLER_MAX_CLIENT_CONN=100"
            echo "POOLER_TENANT_ID=${cfg.poolerTenantId}"
            echo "POOLER_DB_POOL_SIZE=5"
            echo "SUPABASE_PUBLIC_URL=${publicUrl}"
            echo "API_EXTERNAL_URL=${publicUrl}/auth/v1"
            echo "SITE_URL=${cfg.siteUrl}"
            echo "ADDITIONAL_REDIRECT_URLS=${redirectUrls}"
            echo "JWT_EXPIRY=3600"
            echo "DISABLE_SIGNUP=${lib.boolToString cfg.disableSignup}"
            echo "MAILER_URLPATHS_CONFIRMATION=/auth/v1/verify"
            echo "MAILER_URLPATHS_INVITE=/auth/v1/verify"
            echo "MAILER_URLPATHS_RECOVERY=/auth/v1/verify"
            echo "MAILER_URLPATHS_EMAIL_CHANGE=/auth/v1/verify"
            echo "ENABLE_EMAIL_SIGNUP=true"
            echo "ENABLE_EMAIL_AUTOCONFIRM=false"
            echo "SMTP_ADMIN_EMAIL=${cfg.smtp.adminEmail}"
            echo "SMTP_HOST=${cfg.smtp.host}"
            echo "SMTP_PORT=${toString cfg.smtp.port}"
            echo "SMTP_SENDER_NAME=${cfg.smtp.senderName}"
            echo "ENABLE_ANONYMOUS_USERS=false"
            echo "ENABLE_PHONE_SIGNUP=false"
            echo "ENABLE_PHONE_AUTOCONFIRM=false"
            echo "STUDIO_DEFAULT_ORGANIZATION=Default Organization"
            echo "STUDIO_DEFAULT_PROJECT=Default Project"
            echo "OPENAI_API_KEY="
            echo "GLOBAL_S3_BUCKET=${cfg.storage.bucket}"
            echo "REGION=${cfg.storage.region}"
            echo "STORAGE_TENANT_ID=${cfg.poolerTenantId}"
            echo "MINIO_ROOT_USER=unused"
            echo "MINIO_ROOT_PASSWORD=unused-minio-password"
            echo "PGRST_DB_SCHEMAS=public,graphql_public"
            echo "PGRST_DB_MAX_ROWS=1000"
            echo "PGRST_DB_EXTRA_SEARCH_PATH=public"
            echo "FUNCTIONS_VERIFY_JWT=false"
            echo "DOCKER_SOCKET_LOCATION=/var/run/docker.sock"
            echo "GOOGLE_PROJECT_ID=GOOGLE_PROJECT_ID"
            echo "GOOGLE_PROJECT_NUMBER=GOOGLE_PROJECT_NUMBER"
            echo "KONG_HTTP_PORT=${toString cfg.kongPort}"
            echo "KONG_HTTPS_PORT=8443"
            echo "IMGPROXY_AUTO_WEBP=true"
            echo "SUPABASE_PUBLISHABLE_KEY="
            echo "SUPABASE_SECRET_KEY="
            echo "JWT_KEYS="
            echo "JWT_JWKS="
            echo "ANON_KEY_ASYMMETRIC="
            echo "SERVICE_ROLE_KEY_ASYMMETRIC="
          } > ${lib.escapeShellArg envPath}
          chmod 0600 ${lib.escapeShellArg envPath}
        '';
      };

      systemd.services.supabase-stack = {
        description = "Supabase self-hosted Docker Compose stack";
        wantedBy = ["multi-user.target"];
        after = [
          "docker.service"
          "network-online.target"
          "supabase-env-render.service"
        ];
        wants = ["network-online.target"];
        requires = [
          "docker.service"
          "supabase-env-render.service"
        ];
        path = [pkgs.docker pkgs.rsync pkgs.coreutils pkgs.gnugrep pkgs.gnused];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = "30min";
          WorkingDirectory = stackDir;
          ExecStop = "${pkgs.docker}/bin/docker compose -f docker-compose.yml -f docker-compose.garage.yml --env-file .env down --remove-orphans";
        };
        script = ''
          set -euo pipefail
          mkdir -p ${lib.escapeShellArg stackDir}
          # Refresh pinned upstream sources; keep runtime data dirs.
          ${pkgs.rsync}/bin/rsync -a --delete --chmod=u+w \
            --exclude='/.env' \
            --exclude='/docker-compose.garage.yml' \
            --exclude='/volumes/db/data/' \
            --exclude='/volumes/storage/' \
            ${stackSrc}/ ${lib.escapeShellArg stackDir}/
          install -m 0644 ${garageOverlay} ${lib.escapeShellArg stackDir}/docker-compose.garage.yml
          cd ${lib.escapeShellArg stackDir}
          docker compose \
            -f docker-compose.yml \
            -f docker-compose.garage.yml \
            --env-file .env \
            up -d --remove-orphans
        '';
      };

      systemd.services.garage-provision-supabase = lib.mkIf (cfg.storage.provision && config.services.garage.enable) {
        description = "Provision Garage bucket + key for Supabase Storage";
        wantedBy = ["multi-user.target"];
        after = ["garage.service" "supabase-env-render.service"];
        before = ["supabase-stack.service"];
        requires = ["garage.service"];
        path = [pkgs.garage];
        environment = {
          GARAGE_RPC_SECRET_FILE = config.my.secrets.getPath "garage" "rpc_secret";
          GARAGE_ADMIN_ADDR = "127.0.0.1:3903";
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          EnvironmentFile = [secretsEnv];
        };
        script = ''
          set -euo pipefail
          AWS_ID="''${AWS_ACCESS_KEY_ID:-}"
          AWS_SECRET="''${AWS_SECRET_ACCESS_KEY:-}"
          if ! echo "$AWS_ID" | ${pkgs.gnugrep}/bin/grep -E '^GK[0-9a-fA-F]{24}$' >/dev/null 2>&1; then
            if [ -r "${garageS3AccessKey}" ] && [ -r "${garageS3SecretKey}" ]; then
              AWS_ID="$(tr -d '\n' < "${garageS3AccessKey}")"
              AWS_SECRET="$(tr -d '\n' < "${garageS3SecretKey}")"
            else
              echo "garage-provision-supabase: AWS_ACCESS_KEY_ID '$AWS_ID' is invalid and no readable garage-s3 secret found at ${garageS3AccessKey}" >&2
              exit 1
            fi
          fi
          ${pkgs.garage}/bin/garage bucket create ${cfg.storage.bucket} >/dev/null 2>&1 || true
          if ! ${pkgs.garage}/bin/garage key info "$AWS_ID" >/dev/null 2>&1; then
            ${pkgs.garage}/bin/garage key import \
              -n supabase-storage \
              --yes \
              "$AWS_ID" \
              "$AWS_SECRET" >/dev/null 2>&1 || true
          fi
          ${pkgs.garage}/bin/garage bucket allow \
            --read --write ${cfg.storage.bucket} \
            --key "$AWS_ID"
        '';
      };

      my.backups.supabase = lib.mkIf cfg.backup.enable {
        enable = true;
        path = "${cfg.dataDir}/backups";
        frequency = "daily";
        backends = {
          garage = {
            type = "garage-s3";
            bucket = "supabase-backups";
          };
          b2 = {
            type = "b2";
            bucket = null;
            lifecycleKeepPriorVersionsDays = 30;
          };
        };
        backupPrepareCommand = ''
          mkdir -p ${cfg.dataDir}/backups
          ${pkgs.docker}/bin/docker exec supabase-db \
            pg_dump -U postgres -Fc postgres \
            > ${cfg.dataDir}/backups/supabase.dump
        '';
        backupCleanupCommand = ''
          rm -f ${cfg.dataDir}/backups/supabase.dump
        '';
      };

      my.exposure.services.supabase = lib.mkIf cfg.exposure.enable {
        upstream = {
          host = config.my.listenNetworkAddress;
          port = cfg.kongPort;
        };
        router = {inherit (cfg.exposure.router) enable targets;};
        http.virtualHosts = lib.optional (cfg.exposure.domain != null) {
          inherit (cfg.exposure) domain lanOnly useWildcard extraConfig;
        };
      };
    };
  };
}
