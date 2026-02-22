{
  lib,
  pkgs,
  nixosModules,
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
      mkMachineSecret = lib.mkOption {
        type = lib.types.anything;
        default = spec: spec;
      };
      getPath = lib.mkOption {
        type = lib.types.anything;
        default = name: file: "/etc/test-secrets/${name}/${file}";
      };
    };
  };

  nodeBase = {
    networking = {
      useNetworkd = true;
      useDHCP = false;
      firewall.enable = false;
    };
    systemd.network.enable = true;
    system.stateVersion = "25.11";
    environment.systemPackages = with pkgs; [
      awscli2
      curl
      fuse
      rclone
    ];
  };

  paperlessNode = lib.recursiveUpdate nodeBase {
    imports = [
      nixosModules.paperless
      secretsStubModule
    ];

    my.paperless = {
      enable = true;
      openFirewall = false;
      port = 28981;
      address = "127.0.0.1";
      url = "http://127.0.0.1:28981";
      dataDir = "/var/lib/paperless";
      consumptionDir = "/var/lib/paperless/consume";
      mediaDir = "/var/lib/paperless/media";
      ocr.language = "eng";
      database.enableContainer = false;
      database.host = "127.0.0.1";
      database.port = 5432;
      database.name = "paperless";
      database.user = "paperless";
      tika.enable = false;
      s3Consumption = {
        enable = true;
        bucket = "paperless-consume";
        endpoint = "http://127.0.0.1:3900";
        region = "garage";
      };
    };

    services.postgresql = {
      enable = true;
      ensureDatabases = ["paperless"];
      ensureUsers = [
        {
          name = "paperless";
          ensureDBOwnership = true;
        }
      ];
      authentication = pkgs.lib.mkOverride 10 ''
        local   all             all                                     trust
        host    all             all             127.0.0.1/32            trust
      '';
    };

    services.redis.servers.paperless.enable = lib.mkForce false;

    systemd.services.redis-paperless-test = {
      description = "Redis for paperless test";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.redis}/bin/redis-server --bind 127.0.0.1 --port 6379 --save '' --appendonly no";
        Restart = "always";
      };
    };

    systemd.services.minio = {
      description = "MinIO for paperless S3 consumption";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      path = [
        pkgs.coreutils
        pkgs.getent
      ];
      serviceConfig = {
        Type = "simple";
        Environment = [
          "MINIO_ROOT_USER=minioadmin"
          "MINIO_ROOT_PASSWORD=minioadmin123"
        ];
        ExecStart = "${pkgs.minio}/bin/minio server --address 127.0.0.1:3900 --console-address 127.0.0.1:3904 /var/lib/minio";
        Restart = "always";
      };
    };

    systemd.services.minio-bootstrap = {
      description = "Create paperless consumption bucket in MinIO";
      wantedBy = ["multi-user.target"];
      after = ["minio.service"];
      wants = ["minio.service"];
      serviceConfig = {
        Type = "oneshot";
        Environment = [
          "AWS_ACCESS_KEY_ID=minioadmin"
          "AWS_SECRET_ACCESS_KEY=minioadmin123"
          "AWS_DEFAULT_REGION=garage"
        ];
      };
      script = ''
        set -euo pipefail
        for _ in $(seq 1 30); do
          if ${pkgs.awscli2}/bin/aws --endpoint-url http://127.0.0.1:3900 s3api list-buckets >/dev/null 2>&1; then
            break
          fi
          sleep 1
        done

        ${pkgs.awscli2}/bin/aws --endpoint-url http://127.0.0.1:3900 s3api create-bucket --bucket paperless-consume --region garage >/dev/null 2>&1 || true
      '';
    };

    environment.etc = {
      "test-secrets/garage-s3/access_key_id" = {
        mode = "0400";
        text = "minioadmin";
      };
      "test-secrets/garage-s3/secret_access_key" = {
        mode = "0400";
        text = "minioadmin123";
      };
    };
  };
in {
  paperless-s3-consumption = pkgs.testers.runNixOSTest {
    name = "paperless-s3-consumption";
    nodes.machine = paperlessNode;

    testScript = ''
      start_all()

      machine.wait_for_unit("postgresql.service")
      machine.wait_for_unit("redis-paperless-test.service")
      machine.wait_for_unit("minio.service")
      machine.succeed("AWS_ACCESS_KEY_ID=minioadmin AWS_SECRET_ACCESS_KEY=minioadmin123 AWS_DEFAULT_REGION=garage AWS_PAGER= aws --endpoint-url http://127.0.0.1:3900 s3api create-bucket --bucket paperless-consume --region garage >/dev/null 2>&1 || true")
      machine.wait_for_unit("paperless-consumption-mount.service")

      machine.wait_until_succeeds("mount | grep -q '/var/lib/paperless/consume'", timeout=120)

      machine.succeed("printf 'paperless-from-s3\\n' > /tmp/from-s3.txt")
      machine.succeed("AWS_ACCESS_KEY_ID=minioadmin AWS_SECRET_ACCESS_KEY=minioadmin123 AWS_DEFAULT_REGION=garage AWS_PAGER= aws --endpoint-url http://127.0.0.1:3900 s3 cp /tmp/from-s3.txt s3://paperless-consume/from-s3.txt")

      machine.wait_until_succeeds("grep -q '^paperless-from-s3$' /var/lib/paperless/consume/from-s3.txt", timeout=120)

      machine.succeed("printf 'paperless-to-s3\\n' > /var/lib/paperless/consume/from-mount.txt")
      machine.wait_until_succeeds("AWS_ACCESS_KEY_ID=minioadmin AWS_SECRET_ACCESS_KEY=minioadmin123 AWS_DEFAULT_REGION=garage AWS_PAGER= aws --endpoint-url http://127.0.0.1:3900 s3 cp s3://paperless-consume/from-mount.txt /tmp/from-mount.txt && grep -q '^paperless-to-s3$' /tmp/from-mount.txt", timeout=120)
    '';
  };
}
