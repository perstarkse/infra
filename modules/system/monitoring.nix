{
  config.flake.nixosModules.monitoring = {
    lib,
    config,
    pkgs,
    ...
  }: let
    cfg = config.my.monitoring;
    routerCfg = config.my.router;
    routerIp = "${routerCfg.lanSubnet}.1";
  in {
    options.my.monitoring = {
      enable = lib.mkEnableOption "Enable network monitoring";

      netdata = {
        enable = lib.mkEnableOption "Enable Netdata monitoring";
        bindAddress = lib.mkOption {
          type = lib.types.str;
          default = routerIp;
          description = "Address to bind Netdata to";
        };
      };

      ntopng = {
        enable = lib.mkEnableOption "Enable ntopng monitoring";
        httpPort = lib.mkOption {
          type = lib.types.int;
          default = 9999;
          description = "HTTP port for ntopng web interface";
        };
        interfaces = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = ["br-lan" "enp1s0"];
          description = "Interfaces to monitor";
        };
      };

      grafana = {
        enable = lib.mkEnableOption "Enable Grafana dashboard";
        httpAddr = lib.mkOption {
          type = lib.types.str;
          default = routerIp;
          description = "Grafana HTTP bind address";
        };
        httpPort = lib.mkOption {
          type = lib.types.int;
          default = 8888;
          description = "Grafana HTTP port";
        };
        dataDir = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/grafana";
          description = "Grafana data directory";
        };
      };

      prometheus = {
        enable = lib.mkEnableOption "Enable Prometheus monitoring";
        port = lib.mkOption {
          type = lib.types.int;
          default = 9990;
          description = "Prometheus HTTP port";
        };
        exporters = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = {
            node = {
              enable = true;
              enabledCollectors = ["systemd"];
            };
            unbound = {
              enable = true;
            };
          };
          description = "Prometheus exporters configuration";
        };
        scrapeConfigs = lib.mkOption {
          type = lib.types.listOf lib.types.attrs;
          default = [
            {
              job_name = "node";
              static_configs = [{targets = ["localhost:${toString 9100}"];}];
            }
            {
              job_name = "unbound";
              static_configs = [{targets = ["localhost:${toString 9167}"];}];
            }
          ];
          description = "Prometheus scrape configs";
        };
      };
    };

    config = lib.mkIf cfg.enable {
      services.netdata = lib.mkIf cfg.netdata.enable {
        enable = true;
        config.global = {
          "bind to" = cfg.netdata.bindAddress;
        };
      };

      services.ntopng = lib.mkIf cfg.ntopng.enable {
        enable = true;
        httpPort = cfg.ntopng.httpPort;
        interfaces = cfg.ntopng.interfaces;
      };

      services.grafana = lib.mkIf cfg.grafana.enable {
        enable = true;
        settings.server = {
          http_addr = cfg.grafana.httpAddr;
          http_port = cfg.grafana.httpPort;
        };
        dataDir = cfg.grafana.dataDir;
      };

      services.prometheus = lib.mkIf cfg.prometheus.enable {
        enable = true;
        port = cfg.prometheus.port;
        exporters = cfg.prometheus.exporters;
        scrapeConfigs = cfg.prometheus.scrapeConfigs;
      };
    };
  };
} 