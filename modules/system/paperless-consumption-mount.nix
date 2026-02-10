_: {
  config.flake.nixosModules.paperless-consumption-mount = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.paperless-consumption-mount;
  in {
    options.my.paperless-consumption-mount = {
      enable = lib.mkEnableOption "Mount Paperless consumption folder via rclone S3";

      mountPoint = lib.mkOption {
        type = lib.types.path;
        default = "/paperless-consume";
        description = "Local path to mount the consumption folder";
      };

      bucket = lib.mkOption {
        type = lib.types.str;
        default = "paperless-consume";
        description = "S3 bucket name for consumption";
      };

      endpoint = lib.mkOption {
        type = lib.types.str;
        default = "http://10.0.0.1:3900";
        description = "S3 endpoint URL (Garage via router)";
      };

      region = lib.mkOption {
        type = lib.types.str;
        default = "garage";
        description = "S3 region";
      };

      cacheMode = lib.mkOption {
        type = lib.types.enum ["off" "minimal" "writes" "full"];
        default = "writes";
        description = "VFS cache mode for rclone mount";
      };

      cacheMaxSize = lib.mkOption {
        type = lib.types.str;
        default = "1G";
        description = "Maximum size of VFS cache";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "root";
        description = "User to run rclone as and own the mount";
      };

      group = lib.mkOption {
        type = lib.types.str;
        default = "users";
        description = "Group for mount permissions";
      };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [pkgs.rclone];

      my.secrets.allowReadAccess = [
        {
          readers = ["root"];
          path = config.my.secrets.getPath "garage-s3" "access_key_id";
        }
        {
          readers = ["root"];
          path = config.my.secrets.getPath "garage-s3" "secret_access_key";
        }
      ];

      systemd.tmpfiles.rules = [
        "d ${cfg.mountPoint} 0755 ${cfg.user} ${cfg.group} -"
      ];

      systemd.services.paperless-consumption-mount = let
        accessKeyPath = config.my.secrets.getPath "garage-s3" "access_key_id";
        secretKeyPath = config.my.secrets.getPath "garage-s3" "secret_access_key";
        uid = toString config.users.users.${cfg.user}.uid;
        gid = toString config.users.groups.${cfg.group}.gid;
        mountScript = pkgs.writeShellScript "paperless-consumption-mount" ''
          set -euo pipefail
          export RCLONE_S3_ACCESS_KEY_ID="$(cat ${accessKeyPath})"
          export RCLONE_S3_SECRET_ACCESS_KEY="$(cat ${secretKeyPath})"
          exec ${pkgs.rclone}/bin/rclone mount \
            --config /dev/null \
            --s3-provider Other \
            --s3-endpoint ${cfg.endpoint} \
            --s3-region ${cfg.region} \
            --vfs-cache-mode ${cfg.cacheMode} \
            --vfs-cache-max-size ${cfg.cacheMaxSize} \
            --allow-other \
            --uid ${uid} \
            --gid ${gid} \
            --dir-cache-time 1m \
            --poll-interval 30s \
            --vfs-write-back 5s \
            :s3:${cfg.bucket} ${cfg.mountPoint}
        '';
      in {
        description = "Rclone S3 Mount for Paperless Consumption";
        after = ["network-online.target"];
        wants = ["network-online.target"];
        wantedBy = ["multi-user.target"];

        serviceConfig = {
          Type = "notify";
          ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${cfg.mountPoint}";
          ExecStart = mountScript;
          ExecStop = "${pkgs.fuse}/bin/fusermount -u ${cfg.mountPoint}";
          Restart = "on-failure";
          RestartSec = "10s";
        };
      };

      programs.fuse.userAllowOther = true;
    };
  };
}
