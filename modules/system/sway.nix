{inputs, ...}: {
  config.flake.nixosModules.sway = {
    pkgs,
    config,
    lib,
    ...
  }: {
    config = {
      environment.systemPackages = [
        pkgs.sway
        pkgs.wl-clipboard
        pkgs.kitty
      ];

      environment.sessionVariables = {
        NIXOS_OZONE_WL = "1";
        XDG_SESSION_TYPE = "wayland";
      };

      services.displayManager.sessionPackages = [pkgs.sway];
    };
  };
} 