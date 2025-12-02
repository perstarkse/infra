{
  config.flake.nixosModules.unifi-controller = {
    config = {
      services.unifi = {
        enable = true;
      };
    };
  };
}
