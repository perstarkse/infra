{
  config.flake.nixosModules.gnome = {
    services.xserver = {
      enable = true;
      desktopManager.gnome.enable = true;
    };
    services.xserver.displayManager.gdm.enable = true;
  };
}
