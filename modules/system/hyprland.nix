{inputs, ...}: {
  config.flake.nixosModules.hyprland = {
    pkgs,
    config,
    lib,
    ...
  }: let
    cfg = config.my.gui;
  in {
    config = lib.mkIf (cfg.enable && cfg.session == "hyprland") {
      programs.hyprland = {
        enable = true;
        package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
        portalPackage = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
      };

      environment.systemPackages = [
        pkgs.wl-clipboard
      ];

      environment.sessionVariables = {
        NIXOS_OZONE_WL = "1";
        XDG_SESSION_TYPE = "wayland";
      };

      services.displayManager.defaultSession = "hyprland";
    };
  };
}
