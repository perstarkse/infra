{
  config.flake.homeModules.git = {pkgs, ...}: {
    home.packages = [pkgs.delta];

    programs.git = {
      enable = true;
      delta = {
        enable = true;
        options = {
          navigate = true;
          line-numbers = true;
          side-by-side = true;
        };
      };
      extraConfig = {
        merge.conflictstyle = "diff3";
      };
      settings = {
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
  };
}
