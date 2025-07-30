{
  config.flake.nixosModules.steam = {
    config = {
      programs.steam.enable = true;
    };
  };
}
