{ lib, config, ... }:
{
  config.flake.nixosModules.router-dhcp = { lib, config, ... }:
  let
    cfg = config.my.router;
    dhcpCfg = cfg.dhcp;
    helpers = config.routerHelpers or {};
    lanSubnet = helpers.lanSubnet or cfg.lan.subnet;
    lanCidr = helpers.lanCidr or "${lanSubnet}.0/24";
    routerIp = helpers.routerIp or "${lanSubnet}.1";
    dhcpStart = helpers.dhcpStart or "${lanSubnet}.${toString cfg.lan.dhcpRange.start}";
    dhcpEnd = helpers.dhcpEnd or "${lanSubnet}.${toString cfg.lan.dhcpRange.end}";
    machines = cfg.machines;
    enabled = cfg.enable && dhcpCfg.enable;
   in
  {
    config = lib.mkIf enabled {
      services.kea = {
        ctrl-agent = {
          enable = true;
          settings = {
            http-host = "127.0.0.1";
            http-port = 8000;
          };
        };
        dhcp4 = {
          enable = true;
          settings = {
            interfaces-config = {
              interfaces = ["br-lan"];
              re-detect = true;
            };
            "lease-database" = {
              name = dhcpCfg.leaseDatabase;
              type = "memfile";
              persist = true;
              "lfc-interval" = 3600;
            };
            "valid-lifetime" = dhcpCfg.validLifetime;
            "renew-timer" = dhcpCfg.renewTimer;
            "rebind-timer" = dhcpCfg.rebindTimer;
            subnet4 = [
              {
                id = 1;
                subnet = lanCidr;
                pools = [ { pool = "${dhcpStart} - ${dhcpEnd}"; } ];
                reservations = map (machine: {
                  "hw-address" = machine.mac;
                  "ip-address" = "${lanSubnet}.${machine.ip}";
                  hostname = machine.name;
                }) machines;
                "option-data" = [
                  { name = "routers"; data = routerIp; }
                  { name = "domain-name-servers"; data = routerIp; }
                  { name = "domain-name"; data = dhcpCfg.domainName; }
                ];
              }
            ];
          };
        };
      };

      systemd.services.kea-dhcp4-server = {
        wants = ["network-online.target"];
        after = ["systemd-networkd.service" "network-online.target"];
        serviceConfig = {
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };
    };
  };
} 