{
  config.flake.homeModules.zoxide = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.zoxide;
  in {
    options.my.zoxide.enable = lib.mkEnableOption "zoxide with fish integration";

    config = lib.mkIf cfg.enable {
      programs.zoxide = {
        enable = true;
        enableFishIntegration = true;
      };
    };
  };
}
