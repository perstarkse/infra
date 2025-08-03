{inputs, ...}: {
  config.flake.nixosModules.greetd = {
    pkgs,
    config,
    lib,
    ...
  }: let
    cfg = config.my.greetd;
  in {
    options = {
      my.greetd = {
        enable = lib.mkEnableOption "Enable greetd display manager";
        
        sessionType = lib.mkOption {
          type = lib.types.enum ["hyprland" "sway"];
          default = "hyprland";
          description = "The Wayland session type to use with greetd";
        };

        greeting = lib.mkOption {
          type = lib.types.str;
          default = "Welcome!";
          description = "Greeting message displayed by tuigreet";
        };
      };
    };

    config = lib.mkIf cfg.enable {
      services.greetd = {
        enable = true;
        settings = {
          initial_session = {
            command = if cfg.sessionType == "hyprland"
              then "${config.programs.hyprland.package}/bin/Hyprland"
              else "${pkgs.sway}/bin/sway";
            user = config.my.mainUser.name;
          };
          default_session = {
            command = "${pkgs.greetd.tuigreet}/bin/tuigreet --greeting '${cfg.greeting}' --asterisks --remember --remember-user-session --cmd ${
              if cfg.sessionType == "hyprland"
                then "${config.programs.hyprland.package}/bin/Hyprland"
                else "${pkgs.sway}/bin/sway"
            }";
            user = "greeter";
          };
        };
      };

      services.displayManager.defaultSession = if cfg.sessionType == "hyprland" then "hyprland" else "sway";
    };
  };
} 