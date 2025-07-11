{
  config.flake.homeModules.git = {
    config = {
      programs.git = {
        enable = true;
        userName = "Per Stark";
        userEmail = "per@stark.pub";
        extraConfig = {
          init = {
            defaultBranch = "main";
          };
          push = {
            autoSetupRemote = true;
          };
        };
      };
    };
  };
}
