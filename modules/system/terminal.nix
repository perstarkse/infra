{inputs, ...}: {
  config.flake.nixosModules.terminal = {
    pkgs,
    config,
    lib,
    ...
  }: let
    cfg = config.my.gui;
  in {
    config = lib.mkIf (cfg.enable && cfg.terminal == "kitty") {
      environment.systemPackages = [
        pkgs.kitty
      ];
    };
  };
}
