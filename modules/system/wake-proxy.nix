{inputs, ...}: {
  config.flake.nixosModules.wake-proxy = {
    config,
    lib,
    mkStandardExposureOptions,
    ...
  }: let
    cfg = config.services.wakeproxy;
    exposureCfg = config.my.wake-proxy.exposure;
  in {
    imports = [inputs.wol-web-proxy.nixosModules.wake-proxy];

    options.my.wake-proxy.exposure = mkStandardExposureOptions {
      subject = "wake-proxy";
      visibility = "public";
      withAcmeDns01 = true;
    };

    config = lib.mkIf (cfg.enable && exposureCfg.enable) {
      my.exposure.services.wake-proxy = {
        upstream = {
          host = cfg.listenAddress;
          inherit (cfg) port;
        };
        http.virtualHosts = lib.optional (exposureCfg.domain != null) {
          inherit (exposureCfg) domain;
          inherit (exposureCfg) public cloudflareProxied acmeDns01;
          websockets = true;
        };
      };
    };
  };
}
