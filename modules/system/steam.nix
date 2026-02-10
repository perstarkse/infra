{
  config.flake.nixosModules.steam = {
    config = {
      programs.steam = {
        enable = true;
        # remotePlay.openFirewall = true;
      };

      programs.gamescope = {
        enable = true;
        capSysNice = true;
      };
    };
  };
}
