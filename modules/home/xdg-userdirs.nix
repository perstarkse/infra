{
  config.flake.homeModules.xdg-userdirs = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.xdg-userdirs;
  in {
    options.my.xdg-userdirs.enable = lib.mkEnableOption "xdg user directories";

    config = lib.mkIf cfg.enable {
      xdg.userDirs = {
        enable = true;
        # Home Manager 26.05 flipped the default from true to false; keep the
        # legacy behaviour to avoid breaking user scripts that rely on
        # XDG_MUSIC_DIR etc. being exported into the session.
        setSessionVariables = true;
        music = "${config.home.homeDirectory}/music";
        documents = "${config.home.homeDirectory}/documents";
        desktop = "${config.home.homeDirectory}/desktop";
        pictures = "${config.home.homeDirectory}/pictures";
        download = "${config.home.homeDirectory}/download";
      };
    };
  };
}
