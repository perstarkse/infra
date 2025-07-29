{
  config.flake.homeModules.looking-glass-client = {
    programs.looking-glass-client = {
      enable = true;
      settings = {
        input = {
          #grabKeyboardOnFocus = true;
          rawMouse = true;
        };
        spice.alwaysShowCursor = true;
          renderer = {
    doubleBuffer = true;  # Required for NVIDIA Wayland
    eglImplementation = "nvidia";  # MUST specify this
  };
        win = {
          #fullScreen = true;
        };
        audio = {
          micDefault = "allow";
          micShowIndicator = false;
        };
      };
    };
  };
}
