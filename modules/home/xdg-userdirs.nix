{
  config.flake.homeModules.xdg-userdirs = {
    pkgs,
    config,
    ...
  }: {
    config = {
      xdg.userDirs = {
        enable = true;
        music = "${config.home.homeDirectory}/music";
        documents = "${config.home.homeDirectory}/documents";
        desktop = "${config.home.homeDirectory}/desktop";
        pictures = "${config.home.homeDirectory}/pictures";
        download = "${config.home.homeDirectory}/download";
      };
    };
  };
}
