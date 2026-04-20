{
  config.flake.nixosModules.router-dhcp = {
    lib,
    config,
    ...
  }: let
    inherit (lib) filter imap0;
    cfg = config.my.router;
    helpers = config.routerHelpers or {};
    segments = helpers.segments or [];
    enabledSegments = filter (segment: segment.dhcp.enable or false) segments;
    enabled = cfg.enable && (enabledSegments != []);
  in {
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
              interfaces = map (segment: segment.interface) enabledSegments;
              re-detect = true;
            };
            "lease-database" = {
              name = cfg.dhcp.leaseDatabase;
              type = "memfile";
              persist = true;
              "lfc-interval" = 3600;
            };
            "valid-lifetime" = cfg.dhcp.validLifetime;
            "renew-timer" = cfg.dhcp.renewTimer;
            "rebind-timer" = cfg.dhcp.rebindTimer;
            subnet4 =
              imap0
              (index: segment: {
                id = 1 + index;
                subnet = segment.subnetCidr;
                pools = [
                  {pool = "${segment.dhcp.poolStart} - ${segment.dhcp.poolEnd}";}
                ];
                reservations =
                  map (
                    reservation: {
                      "hw-address" = reservation.mac;
                      "ip-address" = reservation.ip;
                      hostname = reservation.name;
                    }
                  )
                  (segment.dhcp.reservations or []);
                "option-data" = [
                  {
                    name = "routers";
                    data = segment.routerIp;
                  }
                  {
                    name = "domain-name-servers";
                    data = segment.routerIp;
                  }
                  {
                    name = "domain-name";
                    data = segment.dhcp.domainName or cfg.dhcp.domainName;
                  }
                ];
              })
              enabledSegments;
          };
        };
      };

      systemd.services.kea-dhcp4-server = {
        wants = [
          "network-online.target"
          "systemd-networkd-wait-online.service"
        ];
        after = [
          "systemd-networkd.service"
          "network-online.target"
          "systemd-networkd-wait-online.service"
        ];
        serviceConfig = {
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };
    };
  };
}
