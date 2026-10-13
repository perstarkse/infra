{
  config.flake.homeModules.zoxide = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.zoxide;
  in {
    options.my.zoxide.enable = lib.mkEnableOption "zoxide with fish and bash integration";

    config = lib.mkIf cfg.enable {
      programs.zoxide = {
        enable = true;
        enableFishIntegration = true;
        # agent's login shell is bash (modules/system/agent-ssh-access.nix);
        # fish covers p.
        enableBashIntegration = true;
      };
    };
  };
}
