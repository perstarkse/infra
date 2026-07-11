{
  config.flake.homeModules.ncspot = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.ncspot;
  in {
    options.my.ncspot.enable = lib.mkEnableOption "ncspot Spotify client";

    config = lib.mkIf cfg.enable {
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
  };
}
