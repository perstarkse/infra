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
        sessionCommand =
          if cfg.session == "hyprland" then "${config.programs.hyprland.package}/bin/Hyprland"
          else if cfg.session == "niri" then "${lib.getExe' config.programs.niri.package "niri-session"}"
          else "${pkgs.sway}/bin/sway --unsupported-gpu";
        tuigreetCommand =
          if cfg.session == "hyprland" then "${config.programs.hyprland.package}/bin/Hyprland"
          else if cfg.session == "niri" then "${lib.getExe' config.programs.niri.package "niri-session"}"
          else "${pkgs.sway}/bin/sway";
      in {
        enable = true;
        settings = {
          initial_session = {
            command = sessionCommand;
            user = config.my.mainUser.name;
          };
          default_session = {
            command = "${pkgs.tuigreet}/bin/tuigreet --greeting '${config.my.greetd.greeting}' --asterisks --remember --remember-user-session --cmd ${tuigreetCommand}";
            user = config.my.mainUser.name;
          };
        };
      };

      services.displayManager.defaultSession =
        if cfg.session == "hyprland"
        then "hyprland"
        else if cfg.session == "niri"
        then "niri"
        else "sway";
    };
  };
}
