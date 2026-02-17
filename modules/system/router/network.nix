{
  config.flake.nixosModules.router-network = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.router;
    helpers = config.routerHelpers or {};
    wan = helpers.wanInterface or cfg.wan.interface;
    lanPorts = helpers.lanPorts or cfg.lan.interfaces;
    lanBridge = helpers.lanBridge or "br-lan";
    lanVlanId = helpers.lanVlanId or 1;
    lanInterface = helpers.lanInterface or "vlan${toString lanVlanId}";
    ulaPrefix = helpers.ulaPrefix or cfg.ipv6.ulaPrefix;
    lanSubnet = helpers.lanSubnet or cfg.lan.subnet;
    routerIp = helpers.routerIp or "${lanSubnet}.1";
    vlans = helpers.vlans or [];
    lanVlan = {
      id = lanVlanId;
      interface = lanInterface;
      routerVlanIp = routerIp;
      cidrPrefix = 24;
    };
    routedVlans = [lanVlan] ++ vlans;
    bridgePortVlanMembership =
      [
        {
          VLAN = lanVlanId;
          PVID = lanVlanId;
          EgressUntagged = lanVlanId;
        }
      ]
      ++ map (vlan: {VLAN = vlan.id;}) vlans;
    bridgeSelfVlanMembership =
      [
        {
          VLAN = lanVlanId;
        }
      ]
      ++ map (vlan: {VLAN = vlan.id;}) vlans;
  in {
    config = lib.mkIf cfg.enable {
      boot.kernel.sysctl = {
        "net.ipv4.conf.all.forwarding" = true;
        "net.ipv4.conf.default.rp_filter" = 2;
        "net.ipv4.conf.${wan}.rp_filter" = 2;
        "net.ipv4.conf.${lanBridge}.rp_filter" = 2;
        "net.ipv4.conf.${lanInterface}.rp_filter" = 2;

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
          extraArgs = map (v: "--interface=${v.interface}") routedVlans;
          timeout = 30;
        };

        netdevs =
          {
            "20-${lanBridge}" = {
              netdevConfig = {
                Kind = "bridge";
                Name = lanBridge;
              };
              bridgeConfig = {
                VLANFiltering = true;
              };
            };
          }
          // lib.listToAttrs (map (
              vlan:
                lib.nameValuePair "30-${vlan.interface}" {
                  netdevConfig = {
                    Name = vlan.interface;
                    Kind = "vlan";
                  };
                  vlanConfig = {
                    Id = vlan.id;
                  };
                }
            )
            routedVlans);

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
                VLAN = map (vlan: vlan.interface) routedVlans;
              };
              linkConfig.RequiredForOnline = "no";
            };

            "35-${lanInterface}" = {
              matchConfig.Name = lanInterface;
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
                  bridgeVLANs = bridgePortVlanMembership;
                  networkConfig = {
                    Bridge = lanBridge;
                    ConfigureWithoutCarrier = true;
                  };
                }
            )
            lanPorts)
          // lib.listToAttrs (map (
              vlan:
                lib.nameValuePair "40-${vlan.interface}" {
                  matchConfig.Name = vlan.interface;
                  address = [
                    "${vlan.routerVlanIp}/${toString vlan.cidrPrefix}"
                  ];
                  networkConfig = {
                    ConfigureWithoutCarrier = true;
                  };
                  linkConfig.RequiredForOnline = "no";
                }
            )
            vlans);
      };

      systemd.services.nftables = {
        after = ["sysinit.target"];
        before = ["network-pre.target"];
        wants = ["network-pre.target"];
      };
    };
  };
}
