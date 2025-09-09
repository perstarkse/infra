{
  config.flake.nixosModules.router-monitoring = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.router;
    mon = cfg.monitoring;
    enabled = cfg.enable && mon.enable;
  in {
    config = lib.mkIf enabled {
      services.netdata = lib.mkIf mon.netdata.enable {
        enable = true;
        config.global = {
          "bind to" = mon.netdata.bindAddress;
        };
      };

      services.ntopng = lib.mkIf mon.ntopng.enable {
        enable = true;
        httpPort = mon.ntopng.httpPort;
        interfaces = mon.ntopng.interfaces;
      };

      services.grafana = lib.mkIf mon.grafana.enable {
        enable = true;
        settings.server = {
          http_addr = mon.grafana.httpAddr;
          http_port = mon.grafana.httpPort;
        };
        dataDir = mon.grafana.dataDir;
      };

      services.prometheus = lib.mkIf mon.prometheus.enable {
        enable = true;
        port = mon.prometheus.port;
        exporters = mon.prometheus.exporters;
        scrapeConfigs = mon.prometheus.scrapeConfigs;
      };
    };
  };
}
