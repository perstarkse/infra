{
  config.flake.homeModules.ncspot = {
    programs.ncspot = {
      enable = true;
      settings = {
        gapless = true;
        use_nerdfont = true;
        ap_port = 443;
        keybindings = {
          "Esc" = "back";
        };
      };
    };
  };
}
