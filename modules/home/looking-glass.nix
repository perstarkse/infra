{
  config.flake.homeModules.looking-glass-client = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.looking-glass-client;
  in {
    options.my.looking-glass-client.enable = lib.mkEnableOption "looking-glass-client for VM display";

    config = lib.mkIf cfg.enable {
      programs.looking-glass-client = {
        enable = true;
        settings = {
          input = {
            rawMouse = true;
          };
          spice.alwaysShowCursor = true;
          audio = {
            micDefault = "allow";
            micShowIndicator = false;
          };
        };
      };
    };
  };
}
