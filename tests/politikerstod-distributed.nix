{
  lib,
  pkgs,
  nixosModules,
  politikerstodPackage,
  ...
}: let
  secretsStubModule = {lib, ...}: {
    options.my.secrets = {
      declarations = lib.mkOption {
        type = lib.types.listOf lib.types.anything;
        default = [];
      };
      allowReadAccess = lib.mkOption {
        type = lib.types.listOf lib.types.anything;
        default = [];
      };
      discover = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
        includeTags = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
        };
      };
      getPath = lib.mkOption {
        type = lib.types.anything;
        default = name: file: "/etc/test-secrets/${name}/${file}";
      };
      mkMachineSecret = lib.mkOption {
        type = lib.types.anything;
        default = spec: spec;
      };
    };
  };

  realPolitikerstodPkg = politikerstodPackage;

  localDbAuth = ''
    local   all             all                                     trust
    host    all             all             127.0.0.1/32            trust
    host    all             all             ::1/128                 trust
  '';

  nodeBase = {
    networking = {
      useNetworkd = true;
      useDHCP = false;
      firewall.enable = false;
    };
    systemd.network.enable = true;
    system.stateVersion = "25.11";
    environment.systemPackages = with pkgs; [
      busybox
      curl
    ];
  };

  serverNode = lib.recursiveUpdate nodeBase {
    virtualisation.vlans = [1];
    imports = [nixosModules.politikerstod secretsStubModule];
    systemd.network.networks."10-eth1" = {
      matchConfig.Name = "eth1";
      address = ["10.0.0.10/24"];
      networkConfig.ConfigureWithoutCarrier = true;
    };

    my.politikerstod = {
      enable = true;
      package = realPolitikerstodPkg;
      startMode = "server";
      openFirewall = false;
      dataDir = "/var/lib/politikerstod";
      database = {
        host = "127.0.0.1";
        enableContainer = false;
      };
      s3.endpoint = "http://127.0.0.1:3900";
    };

    environment.etc."test-secrets/politikerstod/env" = {
      mode = "0400";
      text = ''
        AUTH_ALLOWED_EMAIL_DOMAINS=(?i)(@stark\.pub$)
        OPENAI_API_KEY=test-openai
        AWS_ACCESS_KEY_ID=test-access
        AWS_SECRET_ACCESS_KEY=test-secret
        AWS_REGION=garage
        S3_BUCKET=politikerstod
        S3_ENDPOINT=http://127.0.0.1:3900
        SMTP_HOST=smtp.example.com
        SMTP_PORT=587
        SMTP_USERNAME=test-user
        SMTP_PASSWORD=test-pass
        MAILER_FROM=politikerstod@stark.pub
        JWT_SECRET=test-jwt-secret
        LOCO_ENV=production
      '';
    };

    services.postgresql = {
      authentication = pkgs.lib.mkForce localDbAuth;
      initialScript = pkgs.writeText "politikerstod-test-init.sql" ''
        DO $$
        BEGIN
          IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'politikerstod') THEN
            CREATE ROLE politikerstod LOGIN;
          END IF;
        END$$;
        GRANT ALL PRIVILEGES ON DATABASE politikerstod_prod TO politikerstod;
      '';
    };

    systemd.services.politikerstod-task-export = {
      description = "Export politikerstod task queue over HTTP";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.busybox}/bin/httpd -f -p 18080 -h /var/lib/politikerstod";
        Restart = "always";
      };
    };
  };

  workerNode = lib.recursiveUpdate nodeBase {
    virtualisation.vlans = [1];
    imports = [nixosModules.politikerstod-remote-worker secretsStubModule];
    systemd.network.networks."10-eth1" = {
      matchConfig.Name = "eth1";
      address = ["10.0.0.15/24"];
      networkConfig.ConfigureWithoutCarrier = true;
    };

    my.politikerstod-remote-worker = {
      enable = true;
      package = realPolitikerstodPkg;
      dataDir = "/var/lib/politikerstod";
      workerTags = ["document_process"];
      database.host = "10.0.0.10";
      s3.endpoint = "http://10.0.0.1:3900";
    };

    environment.etc."test-secrets/politikerstod/env" = {
      mode = "0400";
      text = ''
        AUTH_ALLOWED_EMAIL_DOMAINS=(?i)(@stark\.pub$)
        OPENAI_API_KEY=test-openai
        AWS_ACCESS_KEY_ID=test-access
        AWS_SECRET_ACCESS_KEY=test-secret
        AWS_REGION=garage
        S3_BUCKET=politikerstod
        S3_ENDPOINT=http://10.0.0.1:3900
        SMTP_HOST=smtp.example.com
        SMTP_PORT=587
        SMTP_USERNAME=test-user
        SMTP_PASSWORD=test-pass
        MAILER_FROM=politikerstod@stark.pub
        JWT_SECRET=test-jwt-secret
        LOCO_ENV=production
      '';
    };

    services.postgresql.enable = lib.mkForce false;

    systemd.services.politikerstod-worker-test-consumer = {
      description = "Consume queued task in worker test";
      wantedBy = ["multi-user.target"];
      after = ["politikerstod-worker-ready.service"];
      wants = ["politikerstod-worker-ready.service"];
      serviceConfig = {
        Type = "simple";
        ExecStart = pkgs.writeShellScript "politikerstod-worker-test-consumer" ''
          set -euo pipefail
          while [[ ! -f /var/lib/politikerstod/task.queue ]]; do
            sleep 0.5
          done
          cp /var/lib/politikerstod/task.queue /var/lib/politikerstod/task.processed
          sleep infinity
        '';
        Restart = "always";
      };
    };
  };
in {
  politikerstod-distributed = pkgs.testers.runNixOSTest {
    name = "politikerstod-distributed";
    nodes = {
      server = serverNode;
      worker = workerNode;
    };

    testScript = ''
      start_all()

      server.wait_for_unit("politikerstod.service")
      server.wait_for_unit("politikerstod-task-export.service")
      worker.wait_for_unit("politikerstod-worker.service")
      worker.wait_for_unit("politikerstod-worker-test-consumer.service")

      server.wait_until_succeeds("systemctl is-active politikerstod.service", timeout=60)
      worker.wait_until_succeeds("systemctl is-active politikerstod-worker.service", timeout=60)

      server.succeed("systemctl show -p ExecStart politikerstod.service | grep -F -- '--server'")
      worker.succeed("systemctl show -p ExecStart politikerstod-worker.service | grep -F -- '--worker=document_process'")

      server.succeed("printf 'queued-by-server\\n' > /var/lib/politikerstod/task.queue")
      worker.succeed("curl --fail -sS http://10.0.0.10:18080/task.queue -o /var/lib/politikerstod/task.queue")
      worker.wait_until_succeeds("test -f /var/lib/politikerstod/task.processed", timeout=60)
      worker.succeed("grep -q '^queued-by-server$' /var/lib/politikerstod/task.processed")
    '';
  };
}
