{
  config.flake.homeModules.zoxide = {
    programs.zoxide = {
      enable = true;
      enableFishIntegration = true;
    };
  };
}