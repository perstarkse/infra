{
  config.flake.nixosModules.unifi-controller = _: {
    services.unifi = {
      enable = true;
    };
  };
}
