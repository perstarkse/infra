{
  config.flake.nixosModules.router-core = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.router;
    inherit (lib) mkEnableOption mkOption types;
    isHostOctet = s: builtins.match "^([2-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-4])$" s != null;

    machineSubmodule = types.submodule {
      options = {
        name = mkOption {
          type = types.str;
          description = "Machine hostname";
        };
        ip = mkOption {
          type = types.str;
          description = "Static IP address (last octet)";
        };
        mac = mkOption {
          type = types.str;
          description = "MAC address for DHCP reservation";
        };
        portForwards = mkOption {
          type = types.listOf (types.submodule {
            options = {
              port = mkOption {
                type = types.int;
                description = "Port to forward";
              };
              protocol = mkOption {
                type = types.enum ["tcp" "udp" "tcp udp"];
                default = "tcp";
                description = "Protocol to forward";
              };
            };
          });
          default = [];
          description = "Port forwarding rules for this machine";
        };
      };
    };

    serviceSubmodule = types.submodule {
      options = {
        name = mkOption {
          type = types.str;
          description = "Service name";
        };
        target = mkOption {
          type = types.str;
          description = "Target IP or hostname";
        };
      };
    };

    vlanReservationSubmodule = types.submodule {
      options = {
        name = mkOption {
          type = types.str;
          description = "Device label";
        };
        ip = mkOption {
          type = types.str;
          description = "Static IP address (last octet)";
        };
        mac = mkOption {
          type = types.str;
          description = "MAC address for DHCP reservation";
        };
      };
    };

    vlanSubmodule = types.submodule {
      options = {
        name = mkOption {
          type = types.str;
          description = "VLAN label (e.g., camera)";
        };
        id = mkOption {
          type = types.int;
          description = "802.1Q VLAN ID";
        };
        subnet = mkOption {
          type = types.str;
          description = "IPv4 subnet base without CIDR (e.g., 10.0.30)";
        };
        cidrPrefix = mkOption {
          type = types.int;
          default = 24;
          description = "CIDR prefix length for subnet";
        };
        dhcpRange = {
          start = mkOption {
            type = types.int;
            default = 10;
            description = "DHCP start range (last octet)";
          };
          end = mkOption {
            type = types.int;
            default = 200;
            description = "DHCP end range (last octet)";
          };
        };
        wanEgress = mkOption {
          type = types.bool;
          default = true;
          description = "Allow this VLAN to reach WAN";
        };
        reservations = mkOption {
          type = types.listOf vlanReservationSubmodule;
          default = [];
          description = "DHCP reservations within this VLAN";
        };
      };
    };
  in {
    options = {
      my.router = {
        enable = mkEnableOption "Enable router functionality";

        hostname = mkOption {
          type = types.str;
          description = "Router hostname";
        };

        lan = {
          subnet = mkOption {
            type = types.str;
            default = "10.0.0";
            description = "LAN subnet base (e.g., 10.0.0)";
          };
          dhcpRange = {
            start = mkOption {
              type = types.int;
              default = 100;
              description = "DHCP start range (last octet)";
            };
            end = mkOption {
              type = types.int;
              default = 200;
              description = "DHCP end range (last octet)";
            };
          };
          interfaces = mkOption {
            type = types.listOf types.str;
            default = ["enp2s0" "enp3s0" "enp4s0"];
            description = "LAN interfaces to bridge";
          };
        };

        wan = {
          interface = mkOption {
            type = types.str;
            default = "enp1s0";
            description = "WAN interface name";
          };
        };

        ipv6.ulaPrefix = mkOption {
          type = types.str;
          default = "fd00:711a:edcd:7e75";
          description = "ULA prefix for IPv6";
        };

        vlans = mkOption {
          type = types.listOf vlanSubmodule;
          default = [];
          description = "Additional IPv4-only VLAN segments";
        };

        machines = mkOption {
          type = types.listOf machineSubmodule;
          default = [];
          description = "List of machines with static IPs and port forwarding";
        };

        services = mkOption {
          type = types.listOf serviceSubmodule;
          default = [];
          description = "List of services for DNS resolution";
        };

        dhcp = {
          enable = mkEnableOption "Enable DHCP server (Kea)";
          leaseDatabase = mkOption {
            type = types.str;
            default = "/var/lib/kea/dhcp4-leases.csv";
            description = "Path to DHCP lease database";
          };
          validLifetime = mkOption {
            type = types.int;
            default = 86400;
            description = "DHCP lease lifetime in seconds";
          };
          renewTimer = mkOption {
            type = types.int;
            default = 43200;
            description = "DHCP renew timer in seconds";
          };
          rebindTimer = mkOption {
            type = types.int;
            default = 75600;
            description = "DHCP rebind timer in seconds";
          };
          domainName = mkOption {
            type = types.str;
            default = "lan";
            description = "Domain name for DHCP clients";
          };
        };

        dns = {
          enable = mkEnableOption "Enable DNS server (Unbound)";
          upstreamServers = mkOption {
            type = types.listOf types.str;
            default = [
              "1.1.1.1@853#cloudflare-dns.com"
              "1.0.0.1@853#cloudflare-dns.com"
              "2606:4700:4700::1111@853#cloudflare-dns.com"
              "2606:4700:4700::1001@853#cloudflare-dns.com"
            ];
            description = "Upstream DNS servers with TLS";
          };
          localZones = mkOption {
            type = types.listOf types.str;
            default = ["lan."];
            description = "Local DNS zones this router should be authoritative for (include trailing dot).";
          };
        };

        nginx = {
          enable = mkEnableOption "Enable nginx reverse proxy";
          acmeEmail = mkOption {
            type = types.str;
            default = "services@stark.pub";
            description = "Email for ACME/Let's Encrypt certificates";
          };
          ddclient = {
            enable = mkEnableOption "ddclient for dynamic DNS";
            zones = mkOption {
              type = types.listOf (types.submodule {
                options = {
                  zone = mkOption {
                    type = types.str;
                    description = "Cloudflare zone (e.g., stark.pub)";
                  };
                  domains = mkOption {
                    type = types.listOf types.str;
                    description = "Domains to update via ddclient";
                  };
                  passwordFile = mkOption {
                    type = types.path;
                    description = "Path to file containing Cloudflare API token";
                  };
                };
              });
              default = [];
              description = "List of Cloudflare zones with their domains for dynamic DNS updates";
            };
          };
          wildcardCerts = mkOption {
            type = types.listOf (types.submodule {
              options = {
                name = mkOption {
                  type = types.str;
                  description = "Handle for this cert";
                };
                baseDomain = mkOption {
                  type = types.str;
                  description = "Domain base (e.g. stark.pub)";
                };
                dnsProvider = mkOption {
                  type = types.str;
                  description = "lego DNS provider (cloudflare, …)";
                };
                environmentFile = mkOption {
                  type = types.nullOr types.path;
                  default = null;
                };
                group = mkOption {
                  type = types.str;
                  default = "nginx";
                };
              };
            });
            default = [];
            description = "Wildcard certs to issue via ACME DNS‑01.";
          };
          virtualHosts = mkOption {
            type = types.listOf (types.submodule {
              options = {
                domain = mkOption {
                  type = types.str;
                  description = "Domain name for the virtual host";
                };
                target = mkOption {
                  type = types.str;
                  description = "Target machine name (from router.machines) or IP:port";
                };
                targetScheme = mkOption {
                  type = types.enum ["http" "https"];
                  default = "http";
                  description = "Upstream protocol to use when proxying to the target";
                };
                port = mkOption {
                  type = types.int;
                  description = "Target port";
                };
                websockets = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable WebSocket support";
                };
                extraConfig = mkOption {
                  type = types.lines;
                  default = "";
                  description = "Extra nginx configuration";
                };
                lanOnly = mkOption {
                  type = types.bool;
                  default = false;
                  description = "Restrict access to LAN subnets using nginx ACLs";
                };
                cloudflareOnly = mkOption {
                  type = types.bool;
                  default = false;
                  description = "Restrict access to Cloudflare edge IPs only (uses updatable snippet).";
                };
                noAcme = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                  description = "Disable ACME for this vhost";
                };
                useWildcard = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Name of wildcard cert from nginx.wildcardCerts this vhost should use.";
                };
                acmeDns01 = mkOption {
                  type = types.nullOr (types.submodule {
                    options = {
                      dnsProvider = mkOption {
                        type = types.str;
                        description = "lego DNS provider name (e.g., cloudflare)";
                      };
                      environmentFile = mkOption {
                        type = types.nullOr types.path;
                        default = null;
                        description = "Path to an EnvironmentFile exporting provider variables (e.g., CLOUDFLARE_DNS_API_TOKEN=...)";
                      };
                      group = mkOption {
                        type = types.str;
                        default = "nginx";
                        description = "Group that should own read access to issued certificates";
                      };
                    };
                  });
                  default = null;
                  description = "Per-vhost DNS-01 ACME settings";
                };
                basicAuth = mkOption {
                  type = types.nullOr (types.submodule {
                    options = {
                      realm = mkOption {
                        type = types.str;
                        default = "Restricted";
                        description = "Authentication realm shown to users";
                      };
                      htpasswdFile = mkOption {
                        type = types.path;
                        description = "Path to htpasswd file for basic authentication";
                      };
                    };
                  });
                  default = null;
                  description = "Enable HTTP Basic Authentication for this vhost";
                };
              };
            });
            default = [];
            description = "List of virtual hosts to configure";
          };
        };

        monitoring = {
          enable = mkEnableOption "Enable network monitoring";
          netdata = {
            enable = mkEnableOption "Enable Netdata monitoring";
            bindAddress = mkOption {
              type = types.str;
              default = "${cfg.lan.subnet}.1";
              description = "Address to bind Netdata to";
            };
          };
          ntopng = {
            enable = mkEnableOption "Enable ntopng monitoring";
            httpPort = mkOption {
              type = types.int;
              default = 9999;
              description = "HTTP port for ntopng web interface";
            };
            interfaces = mkOption {
              type = types.listOf types.str;
              default = ["br-lan" cfg.wan.interface];
              description = "Interfaces to monitor";
            };
          };
          grafana = {
            enable = mkEnableOption "Enable Grafana dashboard";
            httpAddr = mkOption {
              type = types.str;
              default = "${cfg.lan.subnet}.1";
              description = "Grafana HTTP bind address";
            };
            httpPort = mkOption {
              type = types.int;
              default = 8888;
              description = "Grafana HTTP port";
            };
            dataDir = mkOption {
              type = types.str;
              default = "/var/lib/grafana";
              description = "Grafana data directory";
            };
          };
          prometheus = {
            enable = mkEnableOption "Enable Prometheus monitoring";
            port = mkOption {
              type = types.int;
              default = 9990;
              description = "Prometheus HTTP port";
            };
            exporters = mkOption {
              type = types.attrsOf types.anything;
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
            scrapeConfigs = mkOption {
              type = types.listOf types.attrs;
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

        wireguard = {
          enable = mkEnableOption "Enable WireGuard VPN server";
          interfaceName = mkOption {
            type = types.str;
            default = "wg0";
            description = "WireGuard interface name";
          };
          listenPort = mkOption {
            type = types.int;
            default = 51820;
            description = "WireGuard UDP listen port";
          };
          subnet = mkOption {
            type = types.str;
            default = "10.6.0";
            description = "WireGuard IPv4 subnet base (e.g., 10.6.0)";
          };
          cidrPrefix = mkOption {
            type = types.int;
            default = 24;
            description = "CIDR prefix length for the WireGuard subnet";
          };
          privateKeyFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "Path to server WireGuard private key file";
          };
          routeToLan = mkOption {
            type = types.bool;
            default = true;
            description = "Add route/forwarding between VPN and LAN";
          };
          peers = mkOption {
            type = types.listOf (types.submodule {
              options = {
                name = mkOption {
                  type = types.str;
                  description = "Peer label (e.g., phone name)";
                };
                ip = mkOption {
                  type = types.int;
                  description = "Peer IP last octet within the WireGuard subnet";
                };
                publicKey = mkOption {
                  type = types.nullOr types.str;
                  description = "Peer public key (omit when autoGenerate = true)";
                  default = null;
                };
                persistentKeepalive = mkOption {
                  type = types.nullOr types.int;
                  default = 25;
                  description = "Peer PersistentKeepalive seconds (null to disable)";
                };
                autoGenerate = mkOption {
                  type = types.bool;
                  default = false;
                  description = "Generate peer keypair + client config/QR via secrets and apply peer at runtime (no publicKey needed).";
                };
                endpoint = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Endpoint host:port for generated peer config; defaults to wireguard.defaultEndpoint.";
                };
                dns = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "DNS server to place in generated peer config; defaults to router LAN IP.";
                };
                clientAllowedIPs = mkOption {
                  type = types.listOf types.str;
                  default = ["0.0.0.0/0"];
                  description = "AllowedIPs to place in generated peer config.";
                };
              };
            });
            default = [];
            description = "List of WireGuard peers";
          };
          defaultEndpoint = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Default endpoint host:port for generated peers (overridable per peer).";
          };
          defaultDns = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Default DNS for generated peer configs; defaults to router LAN IP.";
          };
        };
      };

      # Internal helpers for router submodules
      routerHelpers = mkOption {
        type = types.attrs;
        default = {};
        internal = true;
        description = "Derived helper values for router submodules";
      };
    };

    config = lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.lan.interfaces != [];
          message = "my.router.lan.interfaces must include at least one LAN interface";
        }
        {
          assertion = !(lib.elem cfg.wan.interface cfg.lan.interfaces);
          message = "my.router.wan.interface must not also be present in my.router.lan.interfaces";
        }
        {
          assertion = (lib.length cfg.lan.interfaces) == (lib.length (lib.unique cfg.lan.interfaces));
          message = "my.router.lan.interfaces must not contain duplicates";
        }
        {
          assertion =
            cfg.lan.dhcpRange.start
            >= 2
            && cfg.lan.dhcpRange.end <= 254
            && cfg.lan.dhcpRange.start <= cfg.lan.dhcpRange.end;
          message = "my.router.lan.dhcpRange must be within 2..254 and start <= end";
        }
        {
          assertion = (lib.length cfg.machines) == (lib.length (lib.unique (map (m: m.name) cfg.machines)));
          message = "my.router.machines names must be unique";
        }
        {
          assertion = (lib.length cfg.machines) == (lib.length (lib.unique (map (m: m.mac) cfg.machines)));
          message = "my.router.machines MAC addresses must be unique";
        }
        {
          assertion = lib.all (m: isHostOctet m.ip) cfg.machines;
          message = "my.router.machines.<name>.ip must be a numeric host octet in the range 2..254";
        }
        {
          assertion =
            (lib.length (map (m: m.ip) cfg.machines))
            == (lib.length (lib.unique (map (m: m.ip) cfg.machines)));
          message = "my.router.machines IP host octets must be unique";
        }
        {
          assertion = lib.all (m: lib.all (pf: pf.port >= 1 && pf.port <= 65535) m.portForwards) cfg.machines;
          message = "my.router.machines.*.portForwards.*.port must be in range 1..65535";
        }
        {
          assertion = (lib.length cfg.vlans) == (lib.length (lib.unique (map (v: v.name) cfg.vlans)));
          message = "my.router.vlans names must be unique";
        }
        {
          assertion = (lib.length cfg.vlans) == (lib.length (lib.unique (map (v: v.id) cfg.vlans)));
          message = "my.router.vlans IDs must be unique";
        }
        {
          assertion = lib.all (v: v.id >= 2 && v.id <= 4094) cfg.vlans;
          message = "my.router.vlans.*.id must be in range 2..4094 (VLAN 1 is reserved for LAN)";
        }
        {
          assertion =
            (lib.length (map (v: v.subnet) cfg.vlans))
            == (lib.length (lib.unique (map (v: v.subnet) cfg.vlans)));
          message = "my.router.vlans subnets must be unique";
        }
        {
          assertion = !(lib.elem cfg.lan.subnet (map (v: v.subnet) cfg.vlans));
          message = "my.router.vlans subnets must not reuse my.router.lan.subnet";
        }
        {
          assertion =
            lib.all (
              v:
                v.dhcpRange.start
                >= 2
                && v.dhcpRange.end <= 254
                && v.dhcpRange.start <= v.dhcpRange.end
            )
            cfg.vlans;
          message = "my.router.vlans.*.dhcpRange must be within 2..254 and start <= end";
        }
        {
          assertion = lib.all (v: lib.all (r: isHostOctet r.ip) v.reservations) cfg.vlans;
          message = "my.router.vlans.*.reservations.*.ip must be a numeric host octet in the range 2..254";
        }
      ];

      routerHelpers = let
        lanSubnet = cfg.lan.subnet;
        lanCidr = "${lanSubnet}.0/24";
        routerIp = "${lanSubnet}.1";
        lanBridge = "br-lan";
        lanVlanId = 1;
        lanInterface = "vlan${toString lanVlanId}";
        dhcpStart = "${lanSubnet}.${toString cfg.lan.dhcpRange.start}";
        dhcpEnd = "${lanSubnet}.${toString cfg.lan.dhcpRange.end}";
        wgCfg = cfg.wireguard or {};
        wgRouteToLan = wgCfg.routeToLan or true;
        wgSubnet = wgCfg.subnet or "10.6.0";
        wgCidr = "${wgSubnet}.0/${toString (wgCfg.cidrPrefix or 24)}";
        vlanHelpers =
          map (v: let
            subnetCidr = "${v.subnet}.0/${toString v.cidrPrefix}";
            routerVlanIp = "${v.subnet}.1";
          in {
            inherit subnetCidr routerVlanIp;
            inherit (v) name;
            inherit (v) id;
            inherit (v) subnet;
            interface = "vlan${toString v.id}";
            dhcpStart = "${v.subnet}.${toString v.dhcpRange.start}";
            dhcpEnd = "${v.subnet}.${toString v.dhcpRange.end}";
            inherit (v) wanEgress;
            inherit (v) reservations;
            inherit (v) cidrPrefix;
          })
          cfg.vlans;

        lanZone = {
          name = "lan";
          kind = "lan";
          interface = lanInterface;
          subnets = [lanCidr];
          inherit routerIp;
          wanEgress = true;
          allowTo = (lib.optional wgRouteToLan "wireguard") ++ ["libvirt"];
          dhcp = {
            inherit (cfg.dhcp) enable domainName;
            poolStart = dhcpStart;
            poolEnd = dhcpEnd;
            reservations =
              map (machine: {
                inherit (machine) name mac;
                ip = "${lanSubnet}.${machine.ip}";
              })
              cfg.machines;
          };
        };

        vlanZones =
          map (v: {
            inherit (v) name interface wanEgress;
            kind = "vlan";
            subnets = [v.subnetCidr];
            routerIp = v.routerVlanIp;
            allowTo = [];
            dhcp = {
              enable = true;
              inherit (cfg.dhcp) domainName;
              poolStart = v.dhcpStart;
              poolEnd = v.dhcpEnd;
              reservations =
                map (r: {
                  inherit (r) name mac;
                  ip = "${v.subnet}.${r.ip}";
                })
                v.reservations;
            };
          })
          vlanHelpers;

        wgZone = lib.optional (wgCfg.enable or false) {
          name = "wireguard";
          kind = "wireguard";
          interface = wgCfg.interfaceName or "wg0";
          subnets = [wgCidr];
          routerIp = "${wgSubnet}.1";
          wanEgress = true;
          allowTo = (lib.optional wgRouteToLan "lan") ++ ["cni"];
          dhcp.enable = false;
        };

        cniZone = lib.optional (config.systemd.network.enable or false) {
          name = "cni";
          kind = "cni";
          interface = "cni0";
          subnets = [];
          routerIp = null;
          wanEgress = true;
          allowTo = ["lan" "wireguard"];
          dhcp.enable = false;
        };

        libvirtZone = {
          name = "libvirt";
          kind = "libvirt";
          interface = "virbr*";
          subnets = [];
          routerIp = null;
          wanEgress = true;
          allowTo = [];
          dhcp.enable = false;
        };

        wanZone = {
          name = "wan";
          kind = "wan";
          inherit (cfg.wan) interface;
          subnets = [];
          routerIp = null;
          wanEgress = false;
          allowTo = [];
          dhcp.enable = false;
        };
      in {
        inherit lanSubnet lanCidr routerIp lanBridge lanVlanId lanInterface dhcpStart dhcpEnd;
        inherit (cfg.ipv6) ulaPrefix;
        wanInterface = cfg.wan.interface;
        lanPorts = cfg.lan.interfaces;
        vlans = vlanHelpers;
        zones = [lanZone] ++ vlanZones ++ wgZone ++ cniZone ++ [libvirtZone] ++ [wanZone];
      };
    };
  };
}
