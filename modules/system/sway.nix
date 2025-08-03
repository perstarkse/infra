{inputs, ...}: {
  config.flake.nixosModules.sway = {
    pkgs,
    config,
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

      # Ensure sway is available as a session
      services.displayManager.sessionPackages = [pkgs.sway];
    };
  };
} 