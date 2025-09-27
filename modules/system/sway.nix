{
  config.flake.nixosModules.sway = {
    pkgs,
    config,
    lib,
    ...
  }: let
    cfg = config.my.gui;
  in {
    config = lib.mkIf (cfg.enable && cfg.session == "sway") {
      environment.systemPackages = [
        pkgs.sway
        pkgs.wl-clipboard
        pkgs.wireplumber
      ];

      environment.sessionVariables = {
        NIXOS_OZONE_WL = "1";
        XDG_SESSION_TYPE = "wayland";
      };

      services.displayManager.sessionPackages = [pkgs.sway];
    };
  };
}
