{
  config.flake.homeModules.zellij = {
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
}
