{
  config.flake.homeModules.git = {
    config = {
      programs.git = {
        enable = true;
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
  };
}
