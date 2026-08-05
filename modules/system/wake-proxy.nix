{inputs, ...}: {
  config.flake.nixosModules.wake-proxy = {
    config,
    lib,
    mkStandardEndpointsOptions,
    ...
  }: let
    cfg = config.services.wakeproxy;
    endpointsCfg = config.my.wake-proxy.endpoints;
  in {
    imports = [inputs.wol-web-proxy.nixosModules.wake-proxy];

    options.my.wake-proxy.endpoints = mkStandardEndpointsOptions {
      subject = "wake-proxy";
      visibility = "public";
      withAcmeDns01 = true;
    };

    config = lib.mkIf (cfg.enable && endpointsCfg.enable) {
      my.endpoints.services.wake-proxy = {
        upstream = {
          host = cfg.listenAddress;
          inherit (cfg) port;
        };
        http.virtualHosts = lib.optional (endpointsCfg.domain != null) {
          inherit (endpointsCfg) domain;
          inherit (endpointsCfg) public cloudflareProxied acmeDns01;
          websockets = true;
        };
      };
    };
  };
}
