_: {
  config.flake.nixosModules.webdav-garage = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.webdav-garage;
  in {
    options.my.webdav-garage = {
      enable = lib.mkEnableOption "Expose a Garage S3 bucket via WebDAV using rclone";

      bucket = lib.mkOption {
        type = lib.types.str;
        description = "Garage S3 bucket to expose via WebDAV";
      };

      endpoint = lib.mkOption {
        type = lib.types.str;
        default = "http://10.0.0.1:3900";
        description = "Garage S3 endpoint URL";
      };

      region = lib.mkOption {
        type = lib.types.str;
        default = "garage";
        description = "S3 region used by Garage";
      };

      bindAddress = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Address for rclone WebDAV listener (use 127.0.0.1 if behind reverse proxy)";
      };

      port = lib.mkOption {
        type = lib.types.int;
        default = 8081;
        description = "Port for WebDAV";
      };

      readOnly = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Serve bucket in read-only mode";
      };

      htpasswdFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to htpasswd file for basic auth (optional, recommended if not behind authenticated proxy)";
      };

      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Extra arguments to pass to rclone serve webdav";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "root";
        description = "User to run rclone as";
      };

      group = lib.mkOption {
        type = lib.types.str;
        default = "root";
        description = "Group to run rclone as";
      };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [pkgs.rclone];

      my.secrets.allowReadAccess = [
        {
          readers = [cfg.user];
          path = config.my.secrets.getPath "garage-s3" "access_key_id";
        }
        {
          readers = [cfg.user];
          path = config.my.secrets.getPath "garage-s3" "secret_access_key";
        }
      ];

      systemd.services.webdav-garage = let
        accessKeyPath = config.my.secrets.getPath "garage-s3" "access_key_id";
        secretKeyPath = config.my.secrets.getPath "garage-s3" "secret_access_key";
        extraArgsStr = lib.concatStringsSep " " (
          cfg.extraArgs
          ++ lib.optional cfg.readOnly "--read-only"
          ++ lib.optional (cfg.htpasswdFile != null) "--htpasswd ${cfg.htpasswdFile}"
        );
        serveScript = pkgs.writeShellScript "webdav-garage" ''
          set -euo pipefail
          export RCLONE_S3_ACCESS_KEY_ID="$(cat ${accessKeyPath})"
          export RCLONE_S3_SECRET_ACCESS_KEY="$(cat ${secretKeyPath})"
          exec ${pkgs.rclone}/bin/rclone serve webdav \
            --config /dev/null \
            --s3-provider Other \
            --s3-endpoint ${cfg.endpoint} \
            --s3-region ${cfg.region} \
            --addr ${cfg.bindAddress}:${toString cfg.port} \
            --etag-hash MD5 \
            ${extraArgsStr} \
            :s3:${cfg.bucket}
        '';
      in {
        description = "WebDAV server for Garage bucket ${cfg.bucket} via rclone";
        after = ["network-online.target"];
        wants = ["network-online.target"];
        wantedBy = ["multi-user.target"];

        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          ExecStart = serveScript;
          Restart = "on-failure";
          RestartSec = "10s";
        };
      };

      networking.firewall.allowedTCPPorts = lib.mkIf (cfg.bindAddress != "127.0.0.1") [
        cfg.port
      ];
    };
  };
}
