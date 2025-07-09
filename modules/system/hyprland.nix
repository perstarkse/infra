{
  config.flake.nixosModules.hyprland = {pkgs, inputs, ...}: {
    # 1. Enable Hyprland and set up necessary packages and environment variables
    programs.hyprland = {
      enable = true;
      package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
      portalPackage = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
    };

    environment.systemPackages = [
      pkgs.wl-clipboard
      pkgs.kitty # A default terminal is often required by display managers
    ];

    # Enable Wayland session for Qt/GTK applications
    environment.sessionVariables.NIXOS_OZONE_WL = "1";

    # 2. Configure the Display Manager (greetd) to launch Hyprland
    services.displayManager.defaultSession = "hyprland";
    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          # Launch greetd with a terminal greeter that starts Hyprland
          command = "${pkgs.greetd.tuigreet}/bin/tuigreet --cmd ${pkgs.hyprland}/bin/Hyprland";
          user = "greeter";
        };
      };
    };
  };
}
