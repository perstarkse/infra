{
  lib,
  pkgs,
  nixosModules,
  ...
}: let
  testHelpers = import ./lib/test-helpers.nix {inherit lib;};

  secretsStubModule = import ./lib/secrets-stub.nix {
    inherit lib;
    getPathDefault = name: file: "/etc/test-secrets/${name}/${file}";
    mkMachineSecretDefault = spec: spec;
    withDiscover = true;
    withAllowReadAccess = true;
  };

  # Fixed HS256 fixtures (iat=1700000000, exp=+5y, secret below).
  jwtSecret = "test-jwt-secret-at-least-32-chars-long!!";
  anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzAwMDAwMDAwLCJleHAiOjE4NTc2ODAwMDB9.RXSR_V-D7OuHfgsiQc1HzsN3WDlkFBLyMfTs-0n0LvA";
  serviceRoleKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIiwiaXNzIjoic3VwYWJhc2UiLCJpYXQiOjE3MDAwMDAwMDAsImV4cCI6MTg1NzY4MDAwMH0.THy9SSsEezJoMhhk0HQFrhEpSAuNC4VqDkHD4H27QQo";
  # Garage key ID format: GK + 12 hex bytes. Secret: 32 hex bytes.
  storageAccessKey = "GK0123456789abcdef01234567";
  storageSecretKey = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

  supabaseEnvText = ''
    JWT_SECRET=${jwtSecret}
    ANON_KEY=${anonKey}
    SERVICE_ROLE_KEY=${serviceRoleKey}
    POSTGRES_PASSWORD=testpostgrespassword123456
    DASHBOARD_PASSWORD=testdashboardpassword12
    SECRET_KEY_BASE=dGVzdC1zZWNyZXQta2V5LWJhc2UtYXQtbGVhc3QtNjQtY2hhcnMtZm9yLXJlYWx0aW1l
    REALTIME_DB_ENC_KEY=0123456789abcdef
    VAULT_ENC_KEY=0123456789abcdef0123456789abcdef
    PG_META_CRYPTO_KEY=dGVzdC1wZy1tZXRhLWNyeXB0by1rZXktMzI=
    LOGFLARE_PUBLIC_ACCESS_TOKEN=dGVzdC1sb2dmbGFyZS1wdWJsaWMtdG9rZW4=
    LOGFLARE_PRIVATE_ACCESS_TOKEN=dGVzdC1sb2dmbGFyZS1wcml2YXRlLXRva2Vu
    S3_PROTOCOL_ACCESS_KEY_ID=0123456789abcdef0123456789abcdef
    S3_PROTOCOL_ACCESS_KEY_SECRET=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
    AWS_ACCESS_KEY_ID=${storageAccessKey}
    AWS_SECRET_ACCESS_KEY=${storageSecretKey}
    SMTP_USER=smtp-test-user
    SMTP_PASS=smtp-test-pass
  '';

  accountedEnvText = ''
    CRON_SECRET=test-cron-secret-32-bytes-hex-aa
  '';

  nodeBase = testHelpers.mkCommonNode {
    extraPackages = with pkgs; [curl docker garage gnugrep gnused coreutils];
  };

  machine = lib.recursiveUpdate nodeBase {
    imports = [
      nixosModules.options
      nixosModules.docker
      nixosModules.garage
      nixosModules.backups
      nixosModules.supabase
      nixosModules.accounted
      secretsStubModule
    ];

    virtualisation = {
      memorySize = 4096;
      diskSize = 10240;
      cores = 2;
    };

    users.users.test = {
      isNormalUser = true;
      group = "test";
      extraGroups = ["docker"];
    };
    users.groups.test = {};

    my = {
      mainUser.name = "test";
      listenNetworkAddress = "127.0.0.1";
      docker.enable = true;

      garage = {
        enable = true;
        replicationMode = 1;
        rpcPublicAddr = "127.0.0.1:3901";
        zone = "test";
      };

      supabase = {
        enable = true;
        siteUrl = "https://accounting.lan.stark.pub";
        additionalRedirectUrls = [
          "https://accounting.lan.stark.pub/auth/callback"
          "https://accounting.lan.stark.pub/api/auth/callback"
        ];
        storage = {
          endpoint = "http://127.0.0.1:3900";
          bucket = "supabase";
          provision = true;
        };
        # Skip restic backends in VM (no b2/garage-s3 shared secrets).
        backup.enable = false;
        exposure = {
          enable = true;
          domain = "supabase.lan.stark.pub";
          useWildcard = "lanstark";
          lanOnly = true;
          router = {
            enable = true;
            targets = ["io"];
          };
        };
      };

      accounted = {
        enable = true;
        port = 3050;
        address = "127.0.0.1";
        supabaseUrl = "https://supabase.lan.stark.pub";
        exposure = {
          enable = true;
          domain = "accounting.lan.stark.pub";
          useWildcard = "lanstark";
          lanOnly = true;
          router = {
            enable = true;
            targets = ["io"];
          };
        };
      };
    };

    # Do not auto-start heavy compose stacks; tests drive units explicitly.
    systemd.services.supabase-stack.wantedBy = lib.mkForce [];
    systemd.services.accounted-stack.wantedBy = lib.mkForce [];
    systemd.services.accounted-migrate.wantedBy = lib.mkForce [];

    environment.etc = {
      "test-secrets/supabase/env" = {
        text = supabaseEnvText;
        mode = "0400";
      };
      "test-secrets/accounted/env" = {
        text = accountedEnvText;
        mode = "0400";
      };
      "test-secrets/garage/rpc_secret" = {
        text = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
        mode = "0400";
      };
    };
  };
in {
  accounted-system = pkgs.testers.runNixOSTest {
    name = "accounted-system";
    nodes.machine = machine;

    testScript = ''
      machine.start()
      machine.wait_for_unit("docker.service")
      machine.wait_for_unit("garage.service")

      # --- exposure metadata ---
      machine.succeed("test -n \"$(systemctl cat supabase-stack.service)\"")
      machine.succeed("test -n \"$(systemctl cat accounted-stack.service)\"")
      machine.succeed("test -n \"$(systemctl cat accounted-migrate.service)\"")
      machine.succeed("systemctl cat accounted-migrate.service | grep -q supabase-stack.service")
      machine.succeed("systemctl cat accounted-stack.service | grep -q accounted-migrate.service")

      # --- env render (supabase) ---
      machine.succeed("systemctl start supabase-env-render.service")
      machine.wait_for_unit("supabase-env-render.service")
      machine.succeed("test -f /var/lib/supabase/stack/.env")
      machine.succeed("grep -q '^ANON_KEY=${anonKey}$' /var/lib/supabase/stack/.env")
      machine.succeed("grep -q '^SERVICE_ROLE_KEY=${serviceRoleKey}$' /var/lib/supabase/stack/.env")
      machine.succeed("grep -q '^SUPABASE_PUBLIC_URL=https://supabase.lan.stark.pub$' /var/lib/supabase/stack/.env")
      machine.succeed("grep -q '^SITE_URL=https://accounting.lan.stark.pub$' /var/lib/supabase/stack/.env")
      machine.succeed("grep -q 'accounting.lan.stark.pub/auth/callback' /var/lib/supabase/stack/.env")
      machine.succeed("grep -q '^SMTP_HOST=mail-eu.smtp2go.com$' /var/lib/supabase/stack/.env")
      machine.succeed("grep -q '^SMTP_USER=smtp-test-user$' /var/lib/supabase/stack/.env")
      machine.succeed("grep -q '^DISABLE_SIGNUP=false$' /var/lib/supabase/stack/.env")
      machine.succeed("grep -q '^GLOBAL_S3_BUCKET=supabase$' /var/lib/supabase/stack/.env")
      machine.succeed("stat -c '%a' /var/lib/supabase/stack/.env | grep -q '^600$'")

      # --- env render (accounted) ---
      machine.succeed("systemctl start accounted-env-render.service")
      machine.wait_for_unit("accounted-env-render.service")
      machine.succeed("test -f /var/lib/accounted/stack/.env")
      machine.succeed("grep -q '^NEXT_PUBLIC_SUPABASE_URL=https://supabase.lan.stark.pub$' /var/lib/accounted/stack/.env")
      machine.succeed("grep -q '^NEXT_PUBLIC_SUPABASE_ANON_KEY=${anonKey}$' /var/lib/accounted/stack/.env")
      machine.succeed("grep -q '^SUPABASE_SERVICE_ROLE_KEY=${serviceRoleKey}$' /var/lib/accounted/stack/.env")
      machine.succeed("grep -q '^NEXT_PUBLIC_APP_URL=https://accounting.lan.stark.pub$' /var/lib/accounted/stack/.env")
      machine.succeed("grep -q '^NEXT_PUBLIC_SELF_HOSTED=true$' /var/lib/accounted/stack/.env")
      machine.succeed("grep -q '^CRON_SECRET=test-cron-secret-32-bytes-hex-aa$' /var/lib/accounted/stack/.env")
      machine.succeed("grep -q '^IMAGE_TAG=f07a34c$' /var/lib/accounted/stack/.env")
      machine.succeed("stat -c '%a' /var/lib/accounted/stack/.env | grep -q '^600$'")

      # --- Garage layout (single-node) + storage key provision ---
      node_id = machine.succeed("garage node id -q | head -n1").strip()
      short_id = node_id.split("@")[0][:16]
      machine.succeed(f"garage layout assign -z test -c 1G {short_id}")
      machine.succeed("garage layout apply --version 1")
      machine.wait_until_succeeds("garage status | grep -qi healthy", timeout=120)

      machine.succeed("systemctl start garage-provision-supabase.service")
      machine.wait_for_unit("garage-provision-supabase.service")
      machine.succeed("garage bucket info supabase")
      machine.succeed("garage key info ${storageAccessKey} | grep -qi supabase-storage")

      # --- Compose project materialization + config validation (no image pull) ---
      # Stack unit rsyncs first, then compose up (fails offline). Materialization still lands.
      machine.fail("systemctl start supabase-stack.service")
      machine.succeed("test -f /var/lib/supabase/stack/docker-compose.yml")
      machine.succeed("test -f /var/lib/supabase/stack/docker-compose.garage.yml")
      machine.succeed("test -f /var/lib/supabase/stack/volumes/api/kong.yml")
      machine.succeed(
          "cd /var/lib/supabase/stack && docker compose "
          "-f docker-compose.yml -f docker-compose.garage.yml --env-file .env config "
          "| grep -q 'container_name: supabase-kong'"
      )
      machine.succeed(
          "cd /var/lib/supabase/stack && docker compose "
          "-f docker-compose.yml -f docker-compose.garage.yml --env-file .env config "
          "| grep -q 'STORAGE_BACKEND: s3'"
      )
      machine.succeed(
          "cd /var/lib/supabase/stack && docker compose "
          "-f docker-compose.yml -f docker-compose.garage.yml --env-file .env config "
          "| grep -q 'GLOBAL_S3_ENDPOINT: http://127.0.0.1:3900'"
      )
      # Kong declarative routes present (prior failure mode).
      machine.succeed("grep -q 'key-auth' /var/lib/supabase/stack/volumes/api/kong.yml")
      machine.succeed("grep -q 'DASHBOARD' /var/lib/supabase/stack/volumes/api/kong.yml")

      # --- Accounted migrate waits for db (ignore stack dependency; stack is failed offline) ---
      machine.fail(
          "systemctl start --job-mode=ignore-dependencies accounted-migrate.service"
      )
      machine.succeed(
          "journalctl -u accounted-migrate.service --no-pager | grep -qi 'waiting for supabase-db'"
      )

      # --- Accounted compose materialization ---
      machine.fail(
          "systemctl start --job-mode=ignore-dependencies accounted-stack.service"
      )
      machine.succeed("test -f /var/lib/accounted/stack/docker-compose.yml")
      machine.succeed("test -f /var/lib/accounted/stack/docker-compose.lan.yml")
      machine.succeed("test -f /var/lib/accounted/stack/docker/crontab.self-hosted")
      machine.succeed(
          "cd /var/lib/accounted/stack && docker compose "
          "-f docker-compose.yml -f docker-compose.lan.yml --env-file .env config "
          "| grep -q 'ghcr.io/erp-mafia/gnubok'"
      )
      machine.succeed(
          "cd /var/lib/accounted/stack && docker compose "
          "-f docker-compose.yml -f docker-compose.lan.yml --env-file .env config "
          "| grep -E -q 'published: .?3050.?|127.0.0.1:3050:3000'"
      )
      machine.succeed(
          "cd /var/lib/accounted/stack && docker compose "
          "-f docker-compose.yml -f docker-compose.lan.yml --env-file .env config "
          "| grep -E -q 'host_ip: .?127.0.0.1.?|127.0.0.1:3050'"
      )
      machine.succeed(
          "cd /var/lib/accounted/stack && docker compose "
          "-f docker-compose.yml -f docker-compose.lan.yml --env-file .env config "
          "--services | grep -qx cron"
      )

      # --- Exposure domains present in rendered runtime env ---
      machine.succeed("grep -q supabase.lan.stark.pub /var/lib/supabase/stack/.env")
      machine.succeed("grep -q accounting.lan.stark.pub /var/lib/accounted/stack/.env")
      machine.succeed(
          "systemctl show accounted-migrate.service -p Requires | grep -q supabase-stack.service"
      )
      machine.succeed(
          "systemctl show accounted-stack.service -p Requires | grep -q accounted-migrate.service"
      )
    '';
  };
}
