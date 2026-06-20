{
  config.flake.homeModules.git = {pkgs, ...}: {
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
}
