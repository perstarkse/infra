{
  config.flake.nixosModules.unifi-controller = {
    pkgs,
    lib,
    config,
    ...
  }: {
    config = {
      services.unifi = {
        enable = true;
      };
    };
  };
}
