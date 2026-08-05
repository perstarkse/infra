{
  config.flake.nixosModules.greetd = {
    pkgs,
    config,
    lib,
    ...
  }: let
    cfg = config.my.gui;
  in {
    options = {
      my.greetd = {
        enable = lib.mkEnableOption "Enable greetd display manager";

        greeting = lib.mkOption {
          type = lib.types.str;
          default = "Welcome!";
          description = "Greeting message displayed by tuigreet";
        };
      };
    };

    config = lib.mkIf (cfg.enable && config.my.greetd.enable) {
      services.greetd = let
        sessionCommand = "${lib.getExe' config.programs.niri.package "niri-session"}";

        tuigreetSessions =
          "${config.services.displayManager.sessionData.desktops}/share/xsessions:"
          + "${config.services.displayManager.sessionData.desktops}/share/wayland-sessions";

        tuigreetCommand =
          "${pkgs.tuigreet}/bin/tuigreet"
          + " --greeting '${config.my.greetd.greeting}'"
          + " --asterisks"
          + " --remember --remember-user-session"
          + " --sessions ${tuigreetSessions}"
          + " --cmd ${sessionCommand}";
      in {
        enable = true;
        settings = {
          initial_session = {
            command = sessionCommand;
            user = config.my.mainUser.name;
          };
          default_session = {
            command = tuigreetCommand;
            user = config.my.mainUser.name;
          };
        };
      };

      services.displayManager.defaultSession = "niri";
    };
  };
}
