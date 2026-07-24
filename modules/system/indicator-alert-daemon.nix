{inputs, ...}: {
  config.flake.nixosModules.indicator-alert-daemon = {lib, ...}: {
    imports = [inputs.indicator-alert-daemon.nixosModules.default];

    services.indicator-alert-daemon.ntfyUrl = lib.mkDefault "https://ntfy.lan.stark.pub/indicator-alerts";
  };
}
