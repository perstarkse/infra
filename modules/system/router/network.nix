{
  config.flake.nixosModules.router-network = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.router;
    helpers = config.routerHelpers or {};
    wan = helpers.wanInterface or cfg.wan.interface;
    lanIfaces = helpers.lanInterfaces or cfg.lan.interfaces;
    ulaPrefix = helpers.ulaPrefix or cfg.ipv6.ulaPrefix;
    lanSubnet = helpers.lanSubnet or cfg.lan.subnet;
    routerIp = helpers.routerIp or "${lanSubnet}.1";
  in {
    config = lib.mkIf cfg.enable {
      boot.kernel.sysctl = {
        "net.ipv4.conf.all.forwarding" = true;
        "net.ipv4.conf.default.rp_filter" = 2;
        "net.ipv4.conf.${wan}.rp_filter" = 2;
        "net.ipv4.conf.br-lan.rp_filter" = 2;

        "net.ipv6.conf.all.forwarding" = true;
        "net.ipv6.conf.all.accept_ra" = 0;
        "net.ipv6.conf.all.autoconf" = 0;
        "net.ipv6.conf.all.use_tempaddr" = 0;
      };

      boot.kernelParams = [
        "pcie_port_pm=off"
        "igc.eee_enable=0"
      ];

      networking = {
        hostName = cfg.hostname;
        useNetworkd = true;
        useDHCP = false;
        networkmanager.enable = lib.mkForce false;
        firewall.enable = false;
      };

      systemd.network = {
        enable = true;

        netdevs."20-br-lan" = {
          netdevConfig = {
            Kind = "bridge";
            Name = "br-lan";
          };
        };

        networks =
          {
            "20-wan" = {
              matchConfig.Name = wan;
              networkConfig = {
                DHCP = "yes";
                IPv4Forwarding = true;
                IPv6Forwarding = true;
                IPv6AcceptRA = true;
              };
              dhcpV6Config.WithoutRA = "solicit";
              linkConfig.RequiredForOnline = "routable";
            };

            "10-br-lan" = {
              matchConfig.Name = "br-lan";
              address = [
                "${routerIp}/24"
                "${ulaPrefix}::1/64"
              ];
              networkConfig = {
                ConfigureWithoutCarrier = true;
                DHCPPrefixDelegation = true;
                IPv6SendRA = true;
                IPv6AcceptRA = false;
              };
              bridgeConfig = {};
              ipv6Prefixes = [
                {
                  AddressAutoconfiguration = true;
                  OnLink = true;
                  Prefix = "${ulaPrefix}::/64";
                }
              ];
              linkConfig.RequiredForOnline = "no";
            };
          }
          // lib.listToAttrs (map (
              iface:
                lib.nameValuePair "30-${iface}-lan" {
                  matchConfig.Name = iface;
                  networkConfig = {
                    Bridge = "br-lan";
                    ConfigureWithoutCarrier = true;
                  };
                }
            )
            lanIfaces);
      };

      systemd.services.nftables = {
        after = ["sysinit.target"];
        before = ["network-pre.target"];
        wants = ["network-pre.target"];
      };
    };
  };
}
