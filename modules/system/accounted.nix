_: {
  config.flake.nixosModules.accounted = {
    config,
    lib,
    pkgs,
    mkStandardEndpointsOptions,
    ...
  }: let
    cfg = config.my.accounted;

    # Pinned Accounted source: migrations, compose, cron Dockerfile/crontab.
    # imageTag must be a published GHCR tag matching this rev (short SHA).
    accountedSrc = pkgs.fetchFromGitHub {
      owner = "erp-mafia";
      repo = "accounted";
      inherit (cfg) rev;
      inherit (cfg) hash;
    };

    lanOverlay = pkgs.writeText "docker-compose.lan.yml" ''
      services:
        app:
          ports:
            - "''${ACCOUNTED_BIND_ADDR}:''${ACCOUNTED_PORT}:3000"
          extra_hosts:
            - "supabase.lan.stark.pub:10.0.0.1"
          healthcheck:
            test: ["CMD", "node", "-e", "fetch('http://localhost:3000/api/health').then(r=>r.ok?process.exit(0):process.exit(1)).catch(()=>process.exit(1))"]
        cron:
          command: ["-no-reap", "/etc/supercronic/crontab"]
    '';

    supabaseSecrets = config.my.secrets.getPath "supabase" "env";
    accountedSecrets = config.my.secrets.getPath "accounted" "env";
    stackDir = "${cfg.dataDir}/stack";
    envPath = "${stackDir}/.env";
    migrationsDir = "${cfg.dataDir}/migrations";
  in {
    options.my.accounted = {
      enable = lib.mkEnableOption "Accounted (self-hosted Next.js + cron on Supabase)";

      rev = lib.mkOption {
        type = lib.types.str;
        default = "f07a34c51b0e1666cb36e6e498f24a545e2986b0";
        description = "Pinned erp-mafia/accounted commit.";
      };

      hash = lib.mkOption {
        type = lib.types.str;
        default = "sha256-v9bmqmEbB0BRA3lC/E8PJJG81GX6Xo4r65n3a/sVxkk=";
        description = "fetchFromGitHub hash for cfg.rev.";
      };

      imageTag = lib.mkOption {
        type = lib.types.str;
        default = "f07a34c";
        description = "ghcr.io/erp-mafia/gnubok image tag (short SHA matching cfg.rev).";
      };

      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/accounted";
        description = "Compose project + migration ledger.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 3050;
        description = "Host port for the Accounted app (LAN bind).";
      };

      address = lib.mkOption {
        type = lib.types.str;
        default = config.my.listenNetworkAddress;
        description = "Host bind address for the Accounted app port.";
      };

      supabaseUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://supabase.lan.stark.pub";
        description = "NEXT_PUBLIC_SUPABASE_URL (browser + server).";
      };

      endpoints = mkStandardEndpointsOptions {
        subject = "Accounted";
        visibility = "internal";
        withRouter = true;
        withExtraConfigDefault = "";
      };

      # Public Resend inbound webhook for the invoice-inbox extension. Declared
      # on the service (not the router) like the main app: io imports it via
      # my.endpoints.imports, which derives the internal split-horizon DNS
      # record (router LAN IP) and the ddclient/Cloudflare public record.
      invoiceWebhook = lib.mkOption {
        type = lib.types.nullOr (lib.types.submodule {
          options = mkStandardEndpointsOptions {
            subject = "Accounted invoice-inbox webhook";
            visibility = "public";
            withRouter = true;
            withExtraConfigDefault = ''
              if ($uri !~ ^/api/extensions/ext/invoice-inbox/inbound) {
                return 444;
              }
            '';
          };
        });
        default = null;
        description = "Publish the invoice-inbox webhook endpoint (only the inbound path is proxied; everything else returns 444).";
      };
    };

    config = lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = config.virtualisation.docker.enable;
          message = "my.accounted requires virtualisation.docker (enable my.docker).";
        }
        {
          assertion = config.my.supabase.enable;
          message = "my.accounted requires my.supabase.enable = true.";
        }
        {
          assertion = cfg.endpoints.enable -> cfg.endpoints.domain != null;
          message = "my.accounted.endpoints.domain must be set when endpoints are enabled.";
        }
      ];

      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir} 0750 root root -"
        "d ${stackDir} 0750 root root -"
        "d ${migrationsDir} 0750 root root -"
      ];

      systemd.services.accounted-env-render = {
        description = "Render Accounted Docker Compose .env from Clan secrets";
        wantedBy = ["multi-user.target"];
        before = ["accounted-stack.service"];
        after = ["network.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          # ANON_KEY / SERVICE_ROLE_KEY from supabase; CRON_SECRET from accounted.
          EnvironmentFile = [supabaseSecrets accountedSecrets];
        };
        script = let
          appUrl =
            if cfg.endpoints.domain != null
            then "https://${cfg.endpoints.domain}"
            else "http://${cfg.address}:${toString cfg.port}";
        in ''
          set -euo pipefail
          umask 077
          mkdir -p ${lib.escapeShellArg stackDir}
          {
            echo "# Generated by accounted-env-render.service — do not edit."
            echo "NEXT_PUBLIC_SUPABASE_URL=${cfg.supabaseUrl}"
            echo "NEXT_PUBLIC_SUPABASE_ANON_KEY=$ANON_KEY"
            echo "SUPABASE_SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY"
            echo "NEXT_PUBLIC_APP_URL=${appUrl}"
            echo "NEXT_PUBLIC_SELF_HOSTED=true"
            echo "SKATTEVERKET_ENABLED=true"
            echo "CRON_SECRET=$CRON_SECRET"
            echo "IMAGE_TAG=${cfg.imageTag}"
            echo "ACCOUNTED_BIND_ADDR=${cfg.address}"
            echo "ACCOUNTED_PORT=${toString cfg.port}"
            # Optional extras (RESEND_*, AI keys, …) from the accounted generator.
            grep -vE '^[[:space:]]*(CRON_SECRET|#|$)' ${lib.escapeShellArg accountedSecrets} || true
          } > ${lib.escapeShellArg envPath}
          chmod 0600 ${lib.escapeShellArg envPath}
        '';
      };

      # Apply Accounted SQL migrations with a durable ledger (SQL is not idempotent).
      systemd.services.accounted-migrate = {
        description = "Apply Accounted Supabase migrations";
        wantedBy = ["multi-user.target"];
        after = ["supabase-stack.service"];
        requires = ["supabase-stack.service"];
        before = ["accounted-stack.service"];
        path = [pkgs.docker pkgs.coreutils pkgs.gnugrep];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = "30min";
        };
        script = ''
          set -euo pipefail
          mkdir -p ${lib.escapeShellArg migrationsDir}

          echo "waiting for supabase-db..."
          for _ in $(seq 1 90); do
            if docker exec supabase-db pg_isready -U postgres -d postgres >/dev/null 2>&1; then
              break
            fi
            sleep 2
          done
          docker exec supabase-db pg_isready -U postgres -d postgres

          # gotrue/storage-api create auth + storage schemas on first boot.
          echo "waiting for auth.users + storage.buckets..."
          for _ in $(seq 1 90); do
            count="$(docker exec supabase-db psql -U postgres -d postgres -tAc \
              "select count(*) from information_schema.tables where (table_schema='auth' and table_name='users') or (table_schema='storage' and table_name='buckets')")"
            if [ "''${count// /}" = "2" ]; then
              break
            fi
            sleep 2
          done
          count="$(docker exec supabase-db psql -U postgres -d postgres -tAc \
            "select count(*) from information_schema.tables where (table_schema='auth' and table_name='users') or (table_schema='storage' and table_name='buckets')")"
          if [ "''${count// /}" != "2" ]; then
            echo "auth/storage schemas not ready (count=$count)" >&2
            exit 1
          fi

          applied=0
          skipped=0
          shopt -s nullglob
          for f in ${accountedSrc}/supabase/migrations/*.sql; do
            name="$(basename "$f")"
            marker="${migrationsDir}/$name.applied"
            if [ -f "$marker" ]; then
              skipped=$((skipped + 1))
              continue
            fi
            echo "applying $name"
            docker exec -i supabase-db psql -v ON_ERROR_STOP=1 -U postgres -d postgres < "$f"
            sha256sum "$f" > "$marker"
            applied=$((applied + 1))
          done
          echo "migrations: $applied applied, $skipped skipped"
          if [ "$applied" -gt 0 ]; then
            echo "notifying PostgREST to reload schema cache..."
            docker exec -i supabase-db psql -U postgres -d postgres -c "NOTIFY pgrst, 'reload schema';" || true
          fi
        '';
      };

      systemd.services.accounted-stack = {
        description = "Accounted Docker Compose stack (app + cron)";
        wantedBy = ["multi-user.target"];
        after = [
          "docker.service"
          "network-online.target"
          "accounted-env-render.service"
          "accounted-migrate.service"
        ];
        wants = ["network-online.target"];
        requires = [
          "docker.service"
          "accounted-env-render.service"
          "accounted-migrate.service"
        ];
        path = [pkgs.docker pkgs.rsync pkgs.coreutils];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = "30min";
          WorkingDirectory = stackDir;
          ExecStop = "${pkgs.docker}/bin/docker compose -f docker-compose.yml -f docker-compose.lan.yml --env-file .env down --remove-orphans";
        };
        script = ''
          set -euo pipefail
          mkdir -p ${lib.escapeShellArg stackDir}
          ${pkgs.rsync}/bin/rsync -a --delete --chmod=u+w \
            --exclude='/.env' \
            --exclude='/docker-compose.lan.yml' \
            ${accountedSrc}/ ${lib.escapeShellArg stackDir}/
          install -m 0644 ${lanOverlay} ${lib.escapeShellArg stackDir}/docker-compose.lan.yml
          cd ${lib.escapeShellArg stackDir}
          # --build: cron image is built from pinned docker/cron.Dockerfile (digest-pinned).
          docker compose \
            -f docker-compose.yml \
            -f docker-compose.lan.yml \
            --env-file .env \
            up -d --build --remove-orphans
        '';
      };

      my.endpoints.services.accounted = lib.mkIf cfg.endpoints.enable {
        upstream = {
          host = cfg.address;
          inherit (cfg) port;
        };
        router = {inherit (cfg.endpoints.router) enable targets;};
        http.virtualHosts = lib.optional (cfg.endpoints.domain != null) {
          inherit (cfg.endpoints) domain lanOnly useWildcard extraConfig;
        };
      };

      my.endpoints.services.accounted-invoice = lib.mkIf (cfg.invoiceWebhook != null && cfg.invoiceWebhook.enable && cfg.invoiceWebhook.domain != null) {
        upstream = {
          host = cfg.address;
          inherit (cfg) port;
        };
        router = {inherit (cfg.invoiceWebhook.router) enable targets;};
        http.virtualHosts = [
          {
            inherit (cfg.invoiceWebhook) domain public cloudflareProxied extraConfig;
            # Webhook receiver: no WebSocket upgrade needed.
            websockets = false;
          }
        ];
      };
    };
  };
}
