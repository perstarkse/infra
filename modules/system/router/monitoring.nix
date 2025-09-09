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
      services = {
        netdata = lib.mkIf mon.netdata.enable {
          enable = true;
          config.global = {
            "bind to" = mon.netdata.bindAddress;
          };
        };

        ntopng = lib.mkIf mon.ntopng.enable {
          enable = true;
          inherit (mon.ntopng) httpPort;
          inherit (mon.ntopng) interfaces;
        };

        grafana = lib.mkIf mon.grafana.enable {
          enable = true;
          settings.server = {
            http_addr = mon.grafana.httpAddr;
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
