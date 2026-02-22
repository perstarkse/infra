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
      restic
    ];
  };

  backupNode = lib.recursiveUpdate nodeBase {
    imports = [
      nixosModules.backups
      secretsStubModule
    ];

    systemd.services.minio = {
      description = "MinIO test S3 endpoint";
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
        RestartSec = "2s";
      };
    };

    systemd.services.minio-bootstrap = {
      description = "Create backup test bucket in MinIO";
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

        ${pkgs.awscli2}/bin/aws --endpoint-url http://127.0.0.1:3900 s3api create-bucket --bucket restic-integration --region garage >/dev/null 2>&1 || true
      '';
    };

    my.backups = {
      backup = {
        enable = true;
        path = "/var/lib/testdata/backup-source";
        frequency = "daily";
        pruneOpts = [];
        backends.garage = {
          type = "garage-s3";
          bucket = "restic-integration";
          endpoint = "http://127.0.0.1:3900";
          region = "garage";
        };
      };

      restore = {
        enable = true;
        path = "/var/lib/testdata/restore-target";
        backends.garage = {
          type = "garage-s3";
          bucket = "restic-integration";
          endpoint = "http://127.0.0.1:3900";
          region = "garage";
        };
        restore = {
          enable = true;
          backend = "garage";
          snapshot = "latest";
        };
      };
    };

    users.groups.backupowner.gid = 2001;
    users.users.backupowner = {
      isSystemUser = true;
      uid = 2001;
      group = "backupowner";
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

      "test-secrets/restic-backup-garage/repo" = {
        mode = "0400";
        text = "s3:http://127.0.0.1:3900/restic-integration/backup";
      };
      "test-secrets/restic-backup-garage/password" = {
        mode = "0400";
        text = "backup-password";
      };
      "test-secrets/restic-backup-garage/env" = {
        mode = "0400";
        text = ''
          AWS_ACCESS_KEY_ID=minioadmin
          AWS_SECRET_ACCESS_KEY=minioadmin123
          AWS_DEFAULT_REGION=garage
        '';
      };

      "test-secrets/restic-restore-garage/repo" = {
        mode = "0400";
        text = "s3:http://127.0.0.1:3900/restic-integration/restore";
      };
      "test-secrets/restic-restore-garage/password" = {
        mode = "0400";
        text = "restore-password";
      };
      "test-secrets/restic-restore-garage/env" = {
        mode = "0400";
        text = ''
          AWS_ACCESS_KEY_ID=minioadmin
          AWS_SECRET_ACCESS_KEY=minioadmin123
          AWS_DEFAULT_REGION=garage
        '';
      };
    };
  };

  multiBackendNode = lib.recursiveUpdate nodeBase {
    imports = [
      nixosModules.backups
      secretsStubModule
    ];

    systemd.services.minio-a = {
      description = "MinIO A test S3 endpoint";
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
        ExecStart = "${pkgs.minio}/bin/minio server --address 127.0.0.1:3900 --console-address 127.0.0.1:3904 /var/lib/minio-a";
        Restart = "always";
        RestartSec = "2s";
      };
    };

    systemd.services.minio-b = {
      description = "MinIO B test S3 endpoint";
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
        ExecStart = "${pkgs.minio}/bin/minio server --address 127.0.0.1:3905 --console-address 127.0.0.1:3906 /var/lib/minio-b";
        Restart = "always";
        RestartSec = "2s";
      };
    };

    my.backups.multi = {
      enable = true;
      path = "/var/lib/testdata/multi-source";
      frequency = "daily";
      pruneOpts = [];
      backends = {
        primary = {
          type = "garage-s3";
          bucket = "restic-multi-a";
          endpoint = "http://127.0.0.1:3900";
          region = "garage";
        };
        secondary = {
          type = "garage-s3";
          bucket = "restic-multi-b";
          endpoint = "http://127.0.0.1:3905";
          region = "garage";
        };
      };
    };

    environment.etc = {
      "test-secrets/restic-multi-primary/repo" = {
        mode = "0400";
        text = "s3:http://127.0.0.1:3900/restic-multi-a/multi";
      };
      "test-secrets/restic-multi-primary/password" = {
        mode = "0400";
        text = "multi-primary-password";
      };
      "test-secrets/restic-multi-primary/env" = {
        mode = "0400";
        text = ''
          AWS_ACCESS_KEY_ID=minioadmin
          AWS_SECRET_ACCESS_KEY=minioadmin123
          AWS_DEFAULT_REGION=garage
        '';
      };

      "test-secrets/restic-multi-secondary/repo" = {
        mode = "0400";
        text = "s3:http://127.0.0.1:3905/restic-multi-b/multi";
      };
      "test-secrets/restic-multi-secondary/password" = {
        mode = "0400";
        text = "multi-secondary-password";
      };
      "test-secrets/restic-multi-secondary/env" = {
        mode = "0400";
        text = ''
          AWS_ACCESS_KEY_ID=minioadmin
          AWS_SECRET_ACCESS_KEY=minioadmin123
          AWS_DEFAULT_REGION=garage
        '';
      };
    };
  };

  failingBackendNode = lib.recursiveUpdate nodeBase {
    imports = [
      nixosModules.backups
      secretsStubModule
    ];

    systemd.services.minio = {
      description = "MinIO test S3 endpoint";
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
        RestartSec = "2s";
      };
    };

    my.backups.failing = {
      enable = true;
      path = "/var/lib/testdata/failing-source";
      frequency = "daily";
      pruneOpts = [];
      backends.bad = {
        type = "garage-s3";
        bucket = "restic-failing";
        endpoint = "http://127.0.0.1:3900";
        region = "garage";
      };
    };

    environment.etc = {
      "test-secrets/restic-failing-bad/repo" = {
        mode = "0400";
        text = "s3:http://127.0.0.1:3900/restic-failing/failing";
      };
      "test-secrets/restic-failing-bad/password" = {
        mode = "0400";
        text = "failing-password";
      };
      "test-secrets/restic-failing-bad/env" = {
        mode = "0400";
        text = ''
          AWS_ACCESS_KEY_ID=wrong-user
          AWS_SECRET_ACCESS_KEY=wrong-secret
          AWS_DEFAULT_REGION=garage
        '';
      };
    };
  };
in {
  backups-create-restore = pkgs.testers.runNixOSTest {
    name = "backups-create-restore";
    nodes.machine = backupNode;

    testScript = ''
      start_all()

      machine.wait_for_unit("minio.service")
      machine.succeed("AWS_ACCESS_KEY_ID=minioadmin AWS_SECRET_ACCESS_KEY=minioadmin123 AWS_DEFAULT_REGION=garage AWS_PAGER= aws --endpoint-url http://127.0.0.1:3900 s3api create-bucket --bucket restic-integration --region garage >/dev/null 2>&1 || true")

      machine.succeed("mkdir -p /var/lib/testdata/backup-source")
      machine.succeed("printf 'backup-created\\n' > /var/lib/testdata/backup-source/hello.txt")
      machine.succeed("chown backupowner:backupowner /var/lib/testdata/backup-source/hello.txt")
      machine.succeed("systemctl start restic-backups-backup-garage.service")

      machine.wait_until_succeeds(
          "set -a; . /etc/test-secrets/restic-backup-garage/env; restic -r $(cat /etc/test-secrets/restic-backup-garage/repo) --password-file /etc/test-secrets/restic-backup-garage/password snapshots | grep -q snapshot",
          timeout=120,
      )

      machine.succeed("rm -rf /tmp/backup-verify")
      machine.succeed("set -a; . /etc/test-secrets/restic-backup-garage/env; restic -r $(cat /etc/test-secrets/restic-backup-garage/repo) --password-file /etc/test-secrets/restic-backup-garage/password restore latest --target /tmp/backup-verify")
      machine.succeed("grep -q '^backup-created$' /tmp/backup-verify/var/lib/testdata/backup-source/hello.txt")
      machine.succeed("test \"$(stat -c '%u:%g' /tmp/backup-verify/var/lib/testdata/backup-source/hello.txt)\" = '2001:2001'")

      machine.succeed("mkdir -p /var/lib/testdata/restore-source /var/lib/testdata/restore-target")
      machine.succeed("printf 'restored-by-service\\n' > /var/lib/testdata/restore-source/payload.txt")
      machine.succeed("chown backupowner:backupowner /var/lib/testdata/restore-source/payload.txt")
      machine.succeed("set -a; . /etc/test-secrets/restic-restore-garage/env; restic -r $(cat /etc/test-secrets/restic-restore-garage/repo) --password-file /etc/test-secrets/restic-restore-garage/password init || true")
      machine.succeed("set -a; . /etc/test-secrets/restic-restore-garage/env; restic -r $(cat /etc/test-secrets/restic-restore-garage/repo) --password-file /etc/test-secrets/restic-restore-garage/password backup /var/lib/testdata/restore-source")
      machine.succeed("rm -rf /var/lib/testdata/restore-target/*")
      machine.succeed("set -a; . /etc/test-secrets/restic-restore-garage/env; restic -r $(cat /etc/test-secrets/restic-restore-garage/repo) --password-file /etc/test-secrets/restic-restore-garage/password restore latest --target /var/lib/testdata/restore-target")
      machine.succeed("systemctl reset-failed restic-restore-restore.service || true")
      machine.succeed("systemctl start restic-restore-restore.service")
      machine.wait_until_succeeds("systemctl show -p Result --value restic-restore-restore.service | grep -q '^success$'", timeout=120)
      machine.succeed("grep -q '^restored-by-service$' /var/lib/testdata/restore-target/var/lib/testdata/restore-source/payload.txt")
      machine.succeed("test \"$(stat -c '%u:%g' /var/lib/testdata/restore-target/var/lib/testdata/restore-source/payload.txt)\" = '2001:2001'")
    '';
  };

  backups-multi-backend = pkgs.testers.runNixOSTest {
    name = "backups-multi-backend";
    nodes.machine = multiBackendNode;

    testScript = ''
      start_all()

      machine.wait_for_unit("minio-a.service")
      machine.wait_for_unit("minio-b.service")

      machine.succeed("AWS_ACCESS_KEY_ID=minioadmin AWS_SECRET_ACCESS_KEY=minioadmin123 AWS_DEFAULT_REGION=garage AWS_PAGER= aws --endpoint-url http://127.0.0.1:3900 s3api create-bucket --bucket restic-multi-a --region garage >/dev/null 2>&1 || true")
      machine.succeed("AWS_ACCESS_KEY_ID=minioadmin AWS_SECRET_ACCESS_KEY=minioadmin123 AWS_DEFAULT_REGION=garage AWS_PAGER= aws --endpoint-url http://127.0.0.1:3905 s3api create-bucket --bucket restic-multi-b --region garage >/dev/null 2>&1 || true")

      machine.succeed("mkdir -p /var/lib/testdata/multi-source")
      machine.succeed("printf 'multi-backend\\n' > /var/lib/testdata/multi-source/value.txt")

      machine.succeed("systemctl start restic-backups-multi-primary.service")
      machine.succeed("systemctl start restic-backups-multi-secondary.service")

      machine.wait_until_succeeds("set -a; . /etc/test-secrets/restic-multi-primary/env; restic -r $(cat /etc/test-secrets/restic-multi-primary/repo) --password-file /etc/test-secrets/restic-multi-primary/password snapshots | grep -q snapshot", timeout=120)
      machine.wait_until_succeeds("set -a; . /etc/test-secrets/restic-multi-secondary/env; restic -r $(cat /etc/test-secrets/restic-multi-secondary/repo) --password-file /etc/test-secrets/restic-multi-secondary/password snapshots | grep -q snapshot", timeout=120)

      machine.succeed("rm -rf /tmp/multi-restore-a /tmp/multi-restore-b")
      machine.succeed("set -a; . /etc/test-secrets/restic-multi-primary/env; restic -r $(cat /etc/test-secrets/restic-multi-primary/repo) --password-file /etc/test-secrets/restic-multi-primary/password restore latest --target /tmp/multi-restore-a")
      machine.succeed("set -a; . /etc/test-secrets/restic-multi-secondary/env; restic -r $(cat /etc/test-secrets/restic-multi-secondary/repo) --password-file /etc/test-secrets/restic-multi-secondary/password restore latest --target /tmp/multi-restore-b")
      machine.succeed("grep -q '^multi-backend$' /tmp/multi-restore-a/var/lib/testdata/multi-source/value.txt")
      machine.succeed("grep -q '^multi-backend$' /tmp/multi-restore-b/var/lib/testdata/multi-source/value.txt")
    '';
  };

  backups-failing-backend = pkgs.testers.runNixOSTest {
    name = "backups-failing-backend";
    nodes.machine = failingBackendNode;

    testScript = ''
      start_all()

      machine.wait_for_unit("minio.service")
      machine.succeed("AWS_ACCESS_KEY_ID=minioadmin AWS_SECRET_ACCESS_KEY=minioadmin123 AWS_DEFAULT_REGION=garage AWS_PAGER= aws --endpoint-url http://127.0.0.1:3900 s3api create-bucket --bucket restic-failing --region garage >/dev/null 2>&1 || true")

      machine.succeed("mkdir -p /var/lib/testdata/failing-source")
      machine.succeed("printf 'should-not-backup\\n' > /var/lib/testdata/failing-source/value.txt")

      machine.fail("systemctl start restic-backups-failing-bad.service")
      machine.wait_until_succeeds("systemctl show -p Result --value restic-backups-failing-bad.service | grep -q '^exit-code$'", timeout=120)
    '';
  };
}
