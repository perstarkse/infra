{
  config.flake.nixosModules.dhcp = {
    lib,
    config,
    pkgs,
    ...
  }: let
    cfg = config.my.dhcp;
    routerCfg = config.my.router;
    calculated = config.my.router.calculated;
    lanCidr = calculated.lanCidr;
    routerIp = calculated.routerIp;
    dhcpStart = calculated.dhcpStartAddress;
    dhcpEnd = calculated.dhcpEndAddress;
    bridgeName = calculated.bridgeName or "br-lan";
  in {
    options.my.dhcp = {
      enable = lib.mkEnableOption "Enable DHCP server (Kea)";

      leaseDatabase = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/kea/dhcp4-leases.csv";
        description = "Path to DHCP lease database";
      };

      validLifetime = lib.mkOption {
        type = lib.types.int;
        default = 86400;
        description = "DHCP lease lifetime in seconds";
      };

      renewTimer = lib.mkOption {
        type = lib.types.int;
        default = 43200;
        description = "DHCP renew timer in seconds";
      };

      rebindTimer = lib.mkOption {
        type = lib.types.int;
        default = 75600;
        description = "DHCP rebind timer in seconds";
      };

      domainName = lib.mkOption {
        type = lib.types.str;
        default = "lan";
        description = "Domain name for DHCP clients";
      };
    };

    config = lib.mkIf cfg.enable {
      services.kea = {
        ctrl-agent = {
          enable = true;
          settings = {
            http-host = "127.0.0.1"; # Expose only to localhost
            http-port = 8000; # Port for Prometheus to scrape
          };
        };
        dhcp4 = {
          enable = true;
          settings = {
            interfaces-config.interfaces = [bridgeName]; # Kea serves DHCP on the bridge
            lease-database = {
              name = cfg.leaseDatabase;
              type = "memfile";
              persist = true;
              lfc-interval = 3600;
            };
            valid-lifetime = cfg.validLifetime;
            renew-timer = cfg.renewTimer;
            rebind-timer = cfg.rebindTimer;
            subnet4 = [
              {
                id = 1;
                subnet = lanCidr;
                pools = [
                  {
                    pool = "${dhcpStart} - ${dhcpEnd}";
                  }
                ];
                reservations = map (machine: {
                  hw-address = machine.mac;
                  ip-address = "${routerCfg.lanSubnet}.${machine.ip}";
                  hostname = machine.name;
                }) routerCfg.machines;
                option-data = [
                  {
                    name = "routers";
                    data = routerIp;
                  }
                  {
                    name = "domain-name-servers";
                    data = routerIp;
                  }
                  {
                    name = "domain-name";
                    data = cfg.domainName;
                  }
                ];
              }
            ];
          };
        };
      };
    };
  };
} 