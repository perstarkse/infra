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
    };

    config = lib.mkIf cfg.enable {
      boot.kernel.sysctl = {
        "net.ipv4.conf.all.forwarding" = true;
        "net.ipv4.conf.default.rp_filter" = 1;
        "net.ipv4.conf.${cfg.wanInterface}.rp_filter" = 1;
        "net.ipv4.conf.br-lan.rp_filter" = 1;

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
                  iifname "br-lan" accept
                  iifname "${cfg.wanInterface}" ct state established,related accept
                  iifname "${cfg.wanInterface}" ip protocol icmp accept
                  iifname "${cfg.wanInterface}" tcp dport { 80, 443 } accept
                }
                chain forward {
                  type filter hook forward priority 0; policy drop;
                  iifname "br-lan" oifname "${cfg.wanInterface}" accept
                  iifname "br-lan" oifname "br-lan" accept
                  iifname "${cfg.wanInterface}" oifname "br-lan" ct state established,related accept
                  ${lib.concatStringsSep "\n" (lib.mapAttrsToList (machineName: machine: 
                    lib.concatStringsSep "\n" (map (pf: 
                      "iifname \"${cfg.wanInterface}\" oifname \"br-lan\" ip daddr ${lanSubnet}.${machine.ip} ${pf.protocol} dport ${toString pf.port} accept"
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
                      "iifname \"${cfg.wanInterface}\" ${pf.protocol} dport ${toString pf.port} dnat to ${lanSubnet}.${machine.ip}"
                    ) machine.portForwards)
                  ) (lib.listToAttrs (map (m: lib.nameValuePair m.name m) cfg.machines)))}
                }
                chain postrouting {
                  type nat hook postrouting priority 100;
                  oifname "${cfg.wanInterface}" masquerade
                }
              '';
            };
            filterV6 = {
              family = "ip6";
              content = ''
                chain input {
                  type filter hook input priority 0; policy drop;
                  iifname "lo" accept
                  iifname "br-lan" accept
                  iifname "${cfg.wanInterface}" ct state established,related accept
                  iifname "${cfg.wanInterface}" icmpv6 type {
                    destination-unreachable, packet-too-big, time-exceeded,
                    parameter-problem, nd-router-advert, nd-neighbor-solicit,
                    nd-neighbor-advert
                  } accept
                  iifname "${cfg.wanInterface}" udp dport dhcpv6-client udp sport dhcpv6-server accept
                }
                chain forward {
                  type filter hook forward priority 0; policy drop;
                  iifname "br-lan" oifname "${cfg.wanInterface}" accept
                  iifname "${cfg.wanInterface}" oifname "br-lan" ct state established,related accept
                }
              '';
            };
          };
        };
      };

      systemd.network = {
        enable = true;

        # Define the bridge device itself
        netdevs."20-br-lan" = {
          netdevConfig = {
            Kind = "bridge";
            Name = "br-lan";
          };
        };

        networks = {
          # WAN interface configuration
          "20-wan" = {
            matchConfig.Name = cfg.wanInterface;
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
        } // lib.listToAttrs (map (iface: 
          lib.nameValuePair "30-${iface}-lan" {
            matchConfig.Name = iface;
            networkConfig = {
              Bridge = "br-lan";
              ConfigureWithoutCarrier = true;
            };
          }
        ) cfg.lanInterfaces);
      };

      # Make sure nftables comes up after network is initialized
      systemd.services.nftables = {
        after = ["systemd-networkd.service" "network-online.target"];
        wants = ["network-online.target"];
      };

      # Ensure br-lan is brought up early
      systemd.services.systemd-networkd = {
        wantedBy = lib.mkForce ["multi-user.target"]; # keep default
        after = ["network-pre.target"];
      };
    };
  };
} 