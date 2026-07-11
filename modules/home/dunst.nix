{
  config.flake.homeModules.dunst = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.dunst;
  in {
    options.my.dunst.enable = lib.mkEnableOption "dunst notification daemon";

    config = lib.mkIf cfg.enable {
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
