{
  config.flake.nixosModules.router-network = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.router;
    helpers = config.routerHelpers or {};
    wan = helpers.wanInterface or cfg.wan.interface;
    bridgePorts = helpers.bridgePorts or [];
    lanBridge = helpers.lanBridge or "br-lan";
    segments = helpers.segments or [];
    ulaPrefix = helpers.ulaPrefix or cfg.ipv6.ulaPrefix;
    routedInterfaces = map (segment: segment.interface) segments;
    bridgeSelfVlanMembership = map (segment: {VLAN = segment.vlanId;}) segments;
  in {
    config = lib.mkIf cfg.enable {
      boot.kernel.sysctl =
        {
          "net.ipv4.conf.all.forwarding" = true;
          "net.ipv4.conf.default.rp_filter" = 2;
          "net.ipv4.conf.${wan}.rp_filter" = 2;
          "net.ipv4.conf.${lanBridge}.rp_filter" = 2;
        }
        // lib.listToAttrs (map (
            segment: lib.nameValuePair "net.ipv4.conf.${segment.interface}.rp_filter" 2
          )
          segments)
        // {
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
        wait-online = {
          enable = lib.mkForce true;
          extraArgs = map (iface: "--interface=${iface}") routedInterfaces;
          timeout = 30;
        };

        netdevs =
          {
            "20-${lanBridge}" = {
              netdevConfig = {
                Kind = "bridge";
                Name = lanBridge;
              };
              bridgeConfig.VLANFiltering = true;
            };
          }
          // lib.listToAttrs (map (
              segment:
                lib.nameValuePair "30-${segment.interface}" {
                  netdevConfig = {
                    Name = segment.interface;
                    Kind = "vlan";
                  };
                  vlanConfig.Id = segment.vlanId;
                }
            )
            segments);

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

            "10-${lanBridge}" = {
              matchConfig.Name = lanBridge;
              bridgeVLANs = bridgeSelfVlanMembership;
              networkConfig = {
                ConfigureWithoutCarrier = true;
                VLAN = routedInterfaces;
              };
              linkConfig.RequiredForOnline = "no";
            };
          }
          // lib.listToAttrs (map (
              port:
                lib.nameValuePair "30-${port.name}-lan" {
                  matchConfig.Name = port.name;
                  bridgeVLANs = port.memberships;
                  networkConfig = {
                    Bridge = lanBridge;
                    ConfigureWithoutCarrier = true;
                  };
                }
            )
            bridgePorts)
          // lib.listToAttrs (map (
              segment:
                lib.nameValuePair "40-${segment.interface}" ({
                    matchConfig.Name = segment.interface;
                    address = ["${segment.routerIp}/${toString segment.cidrPrefix}"];
                    networkConfig.ConfigureWithoutCarrier = true;
                    linkConfig.RequiredForOnline = "no";
                  }
                  // lib.optionalAttrs segment.isPrimary {
                    address = [
                      "${segment.routerIp}/${toString segment.cidrPrefix}"
                      "${ulaPrefix}::1/64"
                    ];
                    networkConfig = {
                      ConfigureWithoutCarrier = true;
                      DHCPPrefixDelegation = true;
                      IPv6SendRA = true;
                      IPv6AcceptRA = false;
                    };
                    ipv6Prefixes = [
                      {
                        AddressAutoconfiguration = true;
                        OnLink = true;
                        Prefix = "${ulaPrefix}::/64";
                      }
                    ];
                  })
            )
            segments);
      };

      systemd.services.nftables = {
        after = ["sysinit.target"];
        before = ["network-pre.target"];
        wants = ["network-pre.target"];
      };
    };
  };
}
