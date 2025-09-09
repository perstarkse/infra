{
  config.flake.homeModules.kitty = {
    config,
    lib,
    osConfig,
    ...
  }: let
    cfg = osConfig.my.gui;
  in {
    config = lib.mkIf (cfg.enable && cfg.terminal == "kitty") {
      programs.kitty = {
        enable = true;
        shellIntegration.enableFishIntegration = true;
      };

      stylix.targets.kitty.enable = true;
    };
  };
}
