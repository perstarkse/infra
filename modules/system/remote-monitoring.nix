_: {
  config.flake.nixosModules.remote-monitoring = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.remote-monitoring;
    envFile = config.my.secrets.getPath cfg.secretName cfg.secretFile;
  in {
    options.my.remote-monitoring = {
      enable = lib.mkEnableOption "remote monitoring via Gatus";

      secretName = lib.mkOption {
        type = lib.types.str;
        default = "gatus";
        description = "Secret generator name that provides Gatus environment variables.";
      };

      secretFile = lib.mkOption {
        type = lib.types.str;
        default = "env";
        description = "Secret file name that contains Gatus environment variables.";
      };

      secretReaders = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["gatus"];
        description = "Users that should be granted read access to the Gatus secret file.";
      };

      webPort = lib.mkOption {
        type = lib.types.port;
        default = 8080;
        description = "Port for Gatus web UI.";
      };

      settings = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = "Additional Gatus settings merged on top of defaults.";
      };
    };

    config = lib.mkIf cfg.enable {
      users.groups.gatus = {};
      users.users.gatus = {
        isSystemUser = true;
        group = "gatus";
        description = "Gatus monitoring service";
      };

      my.secrets.allowReadAccess =
        map (reader: {
          readers = [reader];
          path = envFile;
        })
        cfg.secretReaders;

      services.gatus = {
        enable = true;
        environmentFile = envFile;
        settings = lib.recursiveUpdate {web.port = cfg.webPort;} cfg.settings;
      };

      # Gatus reads the env file only at startup; the unit is byte-identical
      # across content rotations, so watch the file (restartTriggers on
      # /run/secrets paths would be inert).
      systemd.paths.gatus-env-rotation = {
        description = "Restart gatus on secret rotation";
        wantedBy = ["multi-user.target"];
        pathConfig = {
          PathChanged = [envFile];
          Unit = "gatus-env-rotation-restart.service";
        };
      };

      systemd.services.gatus-env-rotation-restart = {
        description = "Restart gatus after secret rotation";
        serviceConfig = {
          Type = "oneshot";
          ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
          ExecStart = "${pkgs.systemd}/bin/systemctl try-restart gatus.service";
        };
      };

      # Gatus upstream uses DynamicUser; setfacl needs a static passwd entry.
      systemd.services.gatus.serviceConfig.DynamicUser = lib.mkForce false;
    };
  };
}
