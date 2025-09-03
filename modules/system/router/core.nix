{
  lib,
  config,
  pkgs,
  ...
}: {
  config.flake.nixosModules.router-core = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.router;
    inherit (lib) mkEnableOption mkOption types;

    machineSubmodule = types.submodule ({config, ...}: {
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
          type = types.listOf (types.submodule ({...}: {
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
          }));
          default = [];
          description = "Port forwarding rules for this machine";
        };
      };
    });

    serviceSubmodule = types.submodule ({...}: {
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
    });
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
          localZone = mkOption {
            type = types.str;
            default = "lan.";
            description = "Local DNS zone name";
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
            enable = mkOption {
              type = types.bool;
              default = true;
              description = "Enable ddclient for dynamic DNS";
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
                  type = types.nullOr (types.submodule ({...}: {
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
                  }));
                  default = null;
                  description = "Per-vhost DNS-01 ACME settings";
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
              default = ["br-lan" "enp1s0"];
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
            type = types.listOf (types.submodule ({...}: {
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
                  type = types.str;
                  description = "Peer public key";
                };
                persistentKeepalive = mkOption {
                  type = types.nullOr types.int;
                  default = 25;
                  description = "Peer PersistentKeepalive seconds (null to disable)";
                };
              };
            }));
            default = [];
            description = "List of WireGuard peers";
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
      routerHelpers = let
        lanSubnet = cfg.lan.subnet;
        lanCidr = "${lanSubnet}.0/24";
        routerIp = "${lanSubnet}.1";
        dhcpStart = "${lanSubnet}.${toString cfg.lan.dhcpRange.start}";
        dhcpEnd = "${lanSubnet}.${toString cfg.lan.dhcpRange.end}";
      in {
        inherit lanSubnet lanCidr routerIp dhcpStart dhcpEnd;
        ulaPrefix = cfg.ipv6.ulaPrefix;
        wanInterface = cfg.wan.interface;
        lanInterfaces = cfg.lan.interfaces;
      };
    };
  };
}
