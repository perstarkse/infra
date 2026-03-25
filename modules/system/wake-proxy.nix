{inputs, ...}: {
  config.flake.nixosModules.wake-proxy = inputs.wol-web-proxy.nixosModules.wake-proxy;
}
