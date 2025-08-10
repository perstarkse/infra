{
  config.flake.nixosModules.router = {
    lib,
    config,
    pkgs,
    ...
  }: let
    cfg = config.my.router;
    lanSubnet = cfg.lanSubnet;
    lanCidr = "${lanSubnet}.0/24";
    routerIp = "${lanSubnet}.1";
    dhcpStart = "${lanSubnet}.${cfg.dhcpStart}";
    dhcpEnd = "${lanSubnet}.${cfg.dhcpEnd}";
    ulaPrefix = cfg.ulaPrefix;
    # New normalized variables with backward compatibility
    wanIf = if cfg ? wan && cfg.wan.interface != null then cfg.wan.interface else cfg.wanInterface;
    bridgeName = if cfg ? lan && cfg.lan.bridgeName != null then cfg.lan.bridgeName else "br-lan";
    lanIfaces = if cfg ? lan && cfg.lan.interfaces != null && cfg.lan.interfaces != [] then cfg.lan.interfaces else cfg.lanInterfaces;
    wanAllowTcp = (if cfg ? wan && cfg.wan.allowTcpPorts != null then cfg.wan.allowTcpPorts else [80 443]);
    wanAllowUdp = (if cfg ? wan && cfg.wan.allowUdpPorts != null then cfg.wan.allowUdpPorts else []);
    wanAllowDhcpClient = (if cfg ? wan && cfg.wan.allowDhcpClient != null then cfg.wan.allowDhcpClient else true);
    wanAllowIcmp = (if cfg ? wan && cfg.wan.allowIcmp != null then cfg.wan.allowIcmp else true);
    allowTcpRule = lib.optionalString (wanAllowTcp != [])
      ("iifname \"" + wanIf + "\" tcp dport { " + (lib.concatStringsSep ", " (map toString wanAllowTcp)) + " } accept");
    allowUdpRule = lib.optionalString (wanAllowUdp != [])
      ("iifname \"" + wanIf + "\" udp dport { " + (lib.concatStringsSep ", " (map toString wanAllowUdp)) + " } accept");
    allowDhcpRule = lib.optionalString wanAllowDhcpClient
      ("iifname \"" + wanIf + "\" udp sport 67 udp dport 68 accept");
    allowIcmpRule = lib.optionalString wanAllowIcmp
      ("iifname \"" + wanIf + "\" ip protocol icmp accept");
  in {
    options.my.router = {
      enable = lib.mkEnableOption "Enable router functionality";

      lanSubnet = lib.mkOption {
        type = lib.types.str;
        default = "10.0.0";
        description = "LAN subnet base (e.g., 10.0.0)";
      };

      dhcpStart = lib.mkOption {
        type = lib.types.int;
        default = 100;
        description = "DHCP start range (last octet)";
      };

      dhcpEnd = lib.mkOption {
        type = lib.types.int;
        default = 200;
        description = "DHCP end range (last octet)";
      };

      ulaPrefix = lib.mkOption {
        type = lib.types.str;
        default = "fd00:711a:edcd:7e75";
        description = "ULA prefix for IPv6";
      };

      hostname = lib.mkOption {
        type = lib.types.str;
        description = "Router hostname";
      };

      wanInterface = lib.mkOption {
        type = lib.types.str;
        default = "enp1s0";
        description = "WAN interface name";
      };

      lanInterfaces = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["enp2s0" "enp3s0" "enp4s0"];
        description = "LAN interfaces to bridge";
      };

      # New structured options
      wan = {
        interface = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "WAN interface name (overrides wanInterface if set)";
        };
        allowTcpPorts = lib.mkOption {
          type = lib.types.listOf lib.types.int;
          default = [80 443];
          description = "List of TCP ports allowed on WAN input";
        };
        allowUdpPorts = lib.mkOption {
          type = lib.types.listOf lib.types.int;
          default = [];
          description = "List of UDP ports allowed on WAN input";
        };
        allowDhcpClient = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Allow DHCP client traffic on WAN (udp 67->68)";
        };
        allowIcmp = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Allow ICMP on WAN input";
        };
      };

      lan = {
        bridgeName = lib.mkOption {
          type = lib.types.str;
          default = "br-lan";
          description = "Name of the LAN bridge device";
        };
        interfaces = lib.mkOption {
          type = lib.types.nullOr (lib.types.listOf lib.types.str);
          default = null;
          description = "LAN interfaces to enslave to the bridge (overrides lanInterfaces if set)";
        };
      };

      ipv6 = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable IPv6 routing and RA on LAN";
        };
      };

      machines = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Machine hostname";
            };
            ip = lib.mkOption {
              type = lib.types.str;
              description = "Static IP address (last octet)";
            };
            mac = lib.mkOption {
              type = lib.types.str;
              description = "MAC address for DHCP reservation";
            };
            portForwards = lib.mkOption {
              type = lib.types.listOf (lib.types.submodule {
                options = {
                  port = lib.mkOption {
                    type = lib.types.int;
                    description = "Port to forward";
                  };
                  protocol = lib.mkOption {
                    type = lib.types.enum ["tcp" "udp" "tcp udp"];
                    default = "tcp";
                    description = "Protocol to forward";
                  };
                };
              });
              default = [];
              description = "Port forwarding rules for this machine";
            };
          };
        });
        default = [];
        description = "List of machines with static IPs and port forwarding";
      };

      services = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Service name";
            };
            target = lib.mkOption {
              type = lib.types.str;
              description = "Target IP or hostname";
            };
          };
        });
        default = [];
        description = "List of services for DNS resolution";
      };

      # Computed/shared values for other modules to consume
      calculated = {
        lanCidr = lib.mkOption {
          type = lib.types.str;
          description = "Computed LAN CIDR (e.g., 10.0.0.0/24)";
        };
        routerIp = lib.mkOption {
          type = lib.types.str;
          description = "Computed router IPv4 address (e.g., 10.0.0.1)";
        };
        dhcpStartAddress = lib.mkOption {
          type = lib.types.str;
          description = "Computed DHCP range start IPv4 address";
        };
        dhcpEndAddress = lib.mkOption {
          type = lib.types.str;
          description = "Computed DHCP range end IPv4 address";
        };
        machinesByName = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          description = "Attrset of machines keyed by name";
        };
        bridgeName = lib.mkOption {
          type = lib.types.str;
          description = "Computed bridge device name";
        };
        wanInterface = lib.mkOption {
          type = lib.types.str;
          description = "Computed WAN interface name";
        };
      };
    };

    config = lib.mkIf cfg.enable {
      # Expose computed values
      my.router.calculated = {
        lanCidr = lanCidr;
        routerIp = routerIp;
        dhcpStartAddress = dhcpStart;
        dhcpEndAddress = dhcpEnd;
        machinesByName = lib.listToAttrs (map (m: lib.nameValuePair m.name m) cfg.machines);
        bridgeName = bridgeName;
        wanInterface = wanIf;
      };

      boot.kernel.sysctl = {
        "net.ipv4.conf.all.forwarding" = true;
        # Use loose/disabled rp_filter to avoid dropping legitimate bridged/NAT traffic
        "net.ipv4.conf.all.rp_filter" = 0;
        "net.ipv4.conf.default.rp_filter" = 0;
        "net.ipv4.conf.${wanIf}.rp_filter" = 2;
        "net.ipv4.conf.${bridgeName}.rp_filter" = 0;

        "net.ipv6.conf.all.forwarding" = true;
        "net.ipv6.conf.all.accept_ra" = 0;
        "net.ipv6.conf.all.autoconf" = 0;
        "net.ipv6.conf.all.use_tempaddr" = 0;
      };

      boot.kernelParams = [
        "pcie_port_pm=off" # Disable PCIe port power management
        "igc.eee_enable=0" # Disable Energy Efficient Ethernet
      ];

      networking = {
        hostName = cfg.hostname;
        useNetworkd = true;
        useDHCP = false;
        networkmanager.enable = lib.mkForce false;
        firewall.enable = false;

        nftables = {
          enable = true;
          tables = {
            filterV4 = {
              family = "ip";
              content = ''
                chain input {
                  type filter hook input priority 0; policy drop;
                  iifname "lo" accept
                  iifname "${bridgeName}" accept
                  iifname "${wanIf}" ct state established,related accept
                  ${allowIcmpRule}
                  ${allowDhcpRule}
                  ${allowTcpRule}
                  ${allowUdpRule}
                }
                chain forward {
                  type filter hook forward priority 0; policy drop;
                  iifname "${bridgeName}" oifname "${wanIf}" accept
                  iifname "${bridgeName}" oifname "${bridgeName}" accept
                  iifname "${wanIf}" oifname "${bridgeName}" ct state established,related accept
                  ${lib.concatStringsSep "\n" (lib.mapAttrsToList (machineName: machine: 
                    lib.concatStringsSep "\n" (map (pf: 
                      "iifname \"${wanIf}\" oifname \"${bridgeName}\" ip daddr ${lanSubnet}.${machine.ip} ${pf.protocol} dport ${toString pf.port} accept"
                    ) machine.portForwards)
                  ) (lib.listToAttrs (map (m: lib.nameValuePair m.name m) cfg.machines)))}
                }
              '';
            };
            natV4 = {
              family = "ip";
              content = ''
                chain prerouting {
                  type nat hook prerouting priority -100;
                  ${lib.concatStringsSep "\n" (lib.mapAttrsToList (machineName: machine: 
                    lib.concatStringsSep "\n" (map (pf: 
                      "iifname \"${wanIf}\" ${pf.protocol} dport ${toString pf.port} dnat to ${lanSubnet}.${machine.ip}"
                    ) machine.portForwards)
                  ) (lib.listToAttrs (map (m: lib.nameValuePair m.name m) cfg.machines)))}
                }
                chain postrouting {
                  type nat hook postrouting priority 100;
                  oifname "${wanIf}" masquerade
                }
              '';
            };
            filterV6 = {
              family = "ip6";
              content = ''
                chain input {
                  type filter hook input priority 0; policy drop;
                  iifname "lo" accept
                  iifname "${bridgeName}" accept
                  iifname "${wanIf}" ct state established,related accept
                  iifname "${wanIf}" icmpv6 type {
                    destination-unreachable, packet-too-big, time-exceeded,
                    parameter-problem, nd-router-advert, nd-neighbor-solicit,
                    nd-neighbor-advert
                  } accept
                  iifname "${wanIf}" udp dport dhcpv6-client udp sport dhcpv6-server accept
                }
                chain forward {
                  type filter hook forward priority 0; policy drop;
                  iifname "${bridgeName}" oifname "${wanIf}" accept
                  iifname "${wanIf}" oifname "${bridgeName}" ct state established,related accept
                }
              '';
            };
          };
        };
      };

      systemd.network = {
        enable = true;

        # Define the bridge device itself
        netdevs."20-${bridgeName}" = {
          netdevConfig = {
            Kind = "bridge";
            Name = bridgeName;
          };
        };

        networks = {
          # WAN interface configuration
          "20-wan" = {
            matchConfig.Name = wanIf;
            networkConfig = {
              DHCP = "yes";
              IPv4Forwarding = true;
              IPv6Forwarding = true;
              IPv6AcceptRA = true;
            };
            dhcpV6Config.WithoutRA = "solicit";
            linkConfig.RequiredForOnline = "routable";
          };

          # LAN bridge configuration
          "10-${bridgeName}" = {
            matchConfig.Name = bridgeName;
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
        } // lib.listToAttrs (map (iface: 
          lib.nameValuePair "30-${iface}-lan" {
            matchConfig.Name = iface;
            networkConfig = {
              Bridge = bridgeName;
              ConfigureWithoutCarrier = true;
            };
          }
        ) lanIfaces);
      };
    };
  };
} 