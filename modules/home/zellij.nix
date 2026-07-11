{
  config.flake.homeModules.zellij = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.zellij;
  in {
    options.my.zellij.enable = lib.mkEnableOption "zellij terminal multiplexer with fish integration";

    config = lib.mkIf cfg.enable {
      programs.zellij = {
        enable = true;
        enableFishIntegration = true;
        exitShellOnExit = true;
        attachExistingSession = false;
        settings = {
          show_startup_tips = false;
        };
      };
    };
  };
}
