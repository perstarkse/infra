{
  config.flake.nixosModules.niri = {
    pkgs,
    lib,
    config,
    ...
  }: let
    cfg = config.my.gui;
  in {
    config = lib.mkIf (cfg.enable && cfg.session == "niri") {
      programs.niri = {
        enable = true;
        # package = inputs.niri-focus-flash.packages.${pkgs.system}.niri;
      };

      environment.systemPackages = [
        pkgs.wl-clipboard
        pkgs.wireplumber
        pkgs.xwayland-satellite
      ];

      environment.sessionVariables = {
        NIXOS_OZONE_WL = "1";
        XDG_SESSION_TYPE = "wayland";
      };

      services.displayManager.defaultSession = "niri";

      services.gnome.gcr-ssh-agent.enable = lib.mkForce false;
    };
  };
}
