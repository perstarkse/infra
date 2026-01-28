_: {
  config.flake.nixosModules.rclone-s3 = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.rclone-s3;
  in {
    options.my.rclone-s3 = {
      enable = lib.mkEnableOption "Enable rclone S3 mount";

      mountPoint = lib.mkOption {
        type = lib.types.path;
        default = "/s3";
        description = "Path where S3 bucket will be mounted";
      };

      bucket = lib.mkOption {
        type = lib.types.str;
        description = "S3 bucket name to mount";
      };

      endpoint = lib.mkOption {
        type = lib.types.str;
        default = "http://10.0.0.1:3900";
        description = "S3 endpoint URL";
      };

      region = lib.mkOption {
        type = lib.types.str;
        default = "garage";
        description = "S3 region";
      };

      cacheMode = lib.mkOption {
        type = lib.types.enum ["off" "minimal" "writes" "full"];
        default = "full";
        description = "VFS cache mode for rclone mount";
      };

      cacheMaxSize = lib.mkOption {
        type = lib.types.str;
        default = "10G";
        description = "Maximum size of VFS cache";
      };

      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Extra arguments to pass to rclone mount";
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

      systemd.services.rclone-s3-mount = let
        accessKeyPath = config.my.secrets.getPath "garage-s3" "access_key_id";
        secretKeyPath = config.my.secrets.getPath "garage-s3" "secret_access_key";
        extraArgsStr = lib.concatStringsSep " " cfg.extraArgs;
        uid = toString config.users.users.${cfg.user}.uid;
        gid = toString config.users.groups.${cfg.group}.gid;
        mountScript = pkgs.writeShellScript "rclone-s3-mount" ''
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
            --dir-cache-time 5m \
            --poll-interval 10s \
            ${extraArgsStr} \
            :s3:${cfg.bucket} ${cfg.mountPoint}
        '';
      in {
        description = "Rclone S3 Mount for ${cfg.bucket}";
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
