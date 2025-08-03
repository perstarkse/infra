{inputs, ...}: {
  config.flake.nixosModules.hyprland = {
    pkgs,
    config,
    ...
  }: {
    config = {
      programs.hyprland = {
        enable = true;
        package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
        portalPackage = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
      };

      environment.systemPackages = [
        pkgs.wl-clipboard
        pkgs.kitty
      ];

      environment.sessionVariables = {
        NIXOS_OZONE_WL = "1";
        XDG_SESSION_TYPE = "wayland";
      };

      services.displayManager.defaultSession = "hyprland";
    };
  };
}
