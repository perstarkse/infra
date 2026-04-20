{
  config.flake.nixosModules.router-monitoring = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.router;
    mon = cfg.monitoring;
    helpers = config.routerHelpers or {};
    primarySegment = helpers.primarySegment or null;
    bindAddress = if primarySegment != null then primarySegment.routerIp else "${cfg.segments.${cfg.primarySegment}.subnet}.1";
    enabled = cfg.enable && mon.enable;
  in {
    config = lib.mkIf enabled {
      services = {
        netdata = lib.mkIf mon.netdata.enable {
          enable = true;
          config.global = {
            "bind to" = if mon.netdata.bindAddress != null then mon.netdata.bindAddress else bindAddress;
          };
        };

        ntopng = lib.mkIf mon.ntopng.enable {
          enable = true;
          inherit (mon.ntopng) httpPort;
          interfaces = if mon.ntopng.interfaces != [] then mon.ntopng.interfaces else [helpers.lanBridge helpers.wanInterface];
        };

        grafana = lib.mkIf mon.grafana.enable {
          enable = true;
          settings.server = {
            http_addr = if mon.grafana.httpAddr != null then mon.grafana.httpAddr else bindAddress;
            http_port = mon.grafana.httpPort;
          };
          inherit (mon.grafana) dataDir;
        };

        prometheus = lib.mkIf mon.prometheus.enable {
          enable = true;
          inherit (mon.prometheus) port;
          inherit (mon.prometheus) exporters;
          inherit (mon.prometheus) scrapeConfigs;
        };
      };
    };
  };
}
