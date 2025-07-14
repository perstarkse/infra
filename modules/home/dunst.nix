{
  config.flake.homeModules.dunst = {
    config = {
      services.dunst = {
        enable = true;
        settings = {
          global = {
            width = 300;
            height = 240;
            origin = "top-center";
            frame_width = 1;
            word_wrap = true;
            corner_radius = 2;
            alignment = "center";
          };
        };
      };
    };
  };
}
