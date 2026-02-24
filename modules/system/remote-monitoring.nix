_: {
  config.flake.nixosModules.remote-monitoring = {
    config,
    lib,
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
    };
  };
}
