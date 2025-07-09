{inputs, ...}: {
  config.flake.nixosModules.hyprland = {pkgs, ...}: {
    programs.hyprland = {
      enable = true;
      # Use `inputs` from the outer scope here
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
        default_session = {
          command = "${pkgs.greetd.tuigreet}/bin/tuigreet --cmd ${pkgs.hyprland}/bin/Hyprland";
          user = "greeter";
        };
      };
    };
  };
}
