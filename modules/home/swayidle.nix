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

      lockOnSuspend = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Lock the graphical session via loginctl before system sleep.";
      };
    };

    config = lib.mkIf cfg.enable {
      services.swayidle = {
        enable = true;
        # Home Manager 26.05 changed the events shape from a list to an
        # attrset keyed by event name.
        events = lib.optionalAttrs cfg.lockOnSuspend {
          "before-sleep" = "${pkgs.systemd}/bin/loginctl lock-session";
        };
        # Use swayidle's native idlehint instead of shelling out to busctl.
        # idlehint clears IdleHint on start/resume/unlock and targets the
        # session swayidle resolved from logind (more reliable than
        # /session/auto from a transient sh -c).
        # Wayland idle-inhibit (Electron apps, video players, etc.) blocks
        # idlehint from ever firing — check for inhibitors if auto-suspend stalls.
        # -w is only useful when waiting for before-sleep commands.
        extraArgs =
          lib.optionals cfg.lockOnSuspend ["-w"]
          ++ ["idlehint" (toString cfg.idleSeconds)];
      };
    };
  };
}
