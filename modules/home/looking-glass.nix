{
  config.flake.homeModules.looking-glass-client = {
    programs.looking-glass-client = {
      enable = true;
      settings = {
        input = {
          rawMouse = true;
        };
        spice.alwaysShowCursor = true;
        audio = {
          micDefault = "allow";
          micShowIndicator = false;
        };
      };
    };
  };
}
