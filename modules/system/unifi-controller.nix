{
  config.flake.nixosModules.unifi-controller = {
    ...
  }: {
    services.unifi = {
      enable = true;
    };
  };
}
