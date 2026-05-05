{
  config.flake.nixosModules.router-monitoring = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.router;
    mon = cfg.monitoring;
    helpers = config.routerHelpers or (throw "routerHelpers not defined — is the router module loaded?");
    bindAddress = helpers.primaryRouterIp;
    enabled = cfg.enable && mon.enable;
    monitoringServicePorts =
      lib.optionals (enabled && mon.netdata.enable) [
        {
          access = "admin";
          protocol = "tcp";
          port = 19999;
        }
      ]
      ++ lib.optionals (enabled && mon.ntopng.enable) [
        {
          access = "admin";
          protocol = "tcp";
          port = mon.ntopng.httpPort;
        }
      ]
      ++ lib.optionals (enabled && mon.grafana.enable) [
        {
          access = "admin";
          protocol = "tcp";
          port = mon.grafana.httpPort;
        }
      ]
      ++ lib.optionals (enabled && mon.prometheus.enable) [
        {
          access = "admin";
          protocol = "tcp";
          inherit (mon.prometheus) port;
        }
      ];
  in {
    config = lib.mkIf enabled {
      my.router.internalServicePorts = monitoringServicePorts;

      services = {
        netdata = lib.mkIf mon.netdata.enable {
          enable = true;
          config.global = {
            "bind to" =
              if mon.netdata.bindAddress != null
              then mon.netdata.bindAddress
              else bindAddress;
          };
        };

        ntopng = lib.mkIf mon.ntopng.enable {
          enable = true;
          inherit (mon.ntopng) httpPort;
          interfaces =
            if mon.ntopng.interfaces != []
            then mon.ntopng.interfaces
            else [helpers.lanBridge helpers.wanInterface];
        };

        grafana = lib.mkIf mon.grafana.enable {
          enable = true;
          settings.server = {
            http_addr =
              if mon.grafana.httpAddr != null
              then mon.grafana.httpAddr
              else bindAddress;
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
