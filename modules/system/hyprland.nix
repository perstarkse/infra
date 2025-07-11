{inputs, ...}: {
  config.flake.nixosModules.hyprland = {
    pkgs,
    config,
    ...
  }: {
    programs.hyprland = {
      enable = true;
      package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
      portalPackage = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
    };

    environment.systemPackages = [
      pkgs.wl-clipboard
      pkgs.kitty
    ];

    environment.sessionVariables.NIXOS_OZONE_WL = "1";

    services.displayManager.defaultSession = "hyprland";
    services.greetd = {
      enable = true;
      settings = {
        initial_session = {
          command = "${pkgs.hyprland}/bin/Hyprland";
          user = config.systemSettings.mainUser.name;
        };
        default_session = {
          command = "${pkgs.greetd.tuigreet}/bin/tuigreet --greeting 'Welcome to charon!' --asterisks --remember --remember-user-session --cmd ${pkgs.hyprland}/bin/Hyprland";
          user = "greeter";
        };
      };
    };
  };
}
