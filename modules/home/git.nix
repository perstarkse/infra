{
  config.flake.homeModules.git = {
    pkgs,
    lib,
    config,
    ...
  }: let
    cfg = config.my.git;
  in {
    options.my.git.enable = lib.mkEnableOption "git + delta";

    config = lib.mkIf cfg.enable {
      home.packages = [pkgs.delta];

      programs.git = {
        enable = true;
        settings = {
          merge.conflictstyle = "diff3";
          user = {
            name = "Per Stark";
            email = "per@stark.pub";
          };
          init = {
            defaultBranch = "main";
          };
          push = {
            autoSetupRemote = true;
          };
        };
      };

      programs.delta = {
        enable = true;
        enableGitIntegration = true;
        options = {
          navigate = true;
          line-numbers = true;
          side-by-side = true;
        };
      };
    };
  };
}
