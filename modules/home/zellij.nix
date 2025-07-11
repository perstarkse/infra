{
  config.flake.homeModules.zellij = {
    programs.zellij = {
      enable = true;
      enableFishIntegration = true;
      settings = {
        show_startup_tips = false;
      };
    };
  };
}
