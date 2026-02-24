{
  config.flake.homeModules.swayidle = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.swayidle;
  in {
    options.my.swayidle = {
      enable = lib.mkEnableOption "swayidle for idle detection";

      idleSeconds = lib.mkOption {
        type = lib.types.int;
        default = 300;
        description = "Seconds of inactivity before marking session as idle";
      };
    };

    config = lib.mkIf cfg.enable {
      services.swayidle = {
        enable = true;
        events = [
          {
            event = "before-sleep";
            command = "${pkgs.systemd}/bin/loginctl lock-session";
          }
        ];
        timeouts = [
          {
            timeout = cfg.idleSeconds;
            command = "${pkgs.systemd}/bin/busctl call org.freedesktop.login1 /org/freedesktop/login1/session/auto org.freedesktop.login1.Session SetIdleHint b true";
            resumeCommand = "${pkgs.systemd}/bin/busctl call org.freedesktop.login1 /org/freedesktop/login1/session/auto org.freedesktop.login1.Session SetIdleHint b false";
          }
        ];
      };
    };
  };
}
