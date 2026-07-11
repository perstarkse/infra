{
  config.flake.nixosModules.unifi-controller = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.unifi-controller;
  in {
    options.my.unifi-controller.enable = lib.mkEnableOption "UniFi controller";
    config = lib.mkIf cfg.enable {
      services.unifi.enable = true;
    };
  };
}
