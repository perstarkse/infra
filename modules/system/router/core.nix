{
  config.flake.nixosModules.router-core = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.router;
    inherit (lib) all attrByPath attrNames concatMap concatStringsSep filter hasAttr isAttrs listToAttrs mapAttrs mapAttrsToList mkEnableOption mkOption nameValuePair optional optionalString optionals types unique;

    isHostOctet = s: builtins.match "^([2-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-4])$" s != null;
    isIPv4Base = s: builtins.match "^[0-9]{1,3}(\.[0-9]{1,3}){2}$" s != null;
    reservedZoneNames = ["wan" "wireguard" "cni" "libvirt"];

    reservationSubmodule = types.submodule {
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

    reachRuleSubmodule = types.submodule {
      options = {
        segment = mkOption {
          type = types.str;
          description = "Target segment or special zone name";
        };
        all = mkOption {
          type = types.bool;
          default = false;
          description = "Allow all traffic to the target";
        };
        icmp = mkOption {
          type = types.bool;
          default = false;
          description = "Allow ICMP/ICMPv6 to the target";
        };
        tcpPorts = mkOption {
          type = types.listOf types.int;
          default = [];
          description = "Allowed TCP destination ports to the target";
        };
        udpPorts = mkOption {
          type = types.listOf types.int;
          default = [];
          description = "Allowed UDP destination ports to the target";
        };
      };
    };

    machineSubmodule = types.submodule {
      options = {
        name = mkOption {
          type = types.str;
          description = "Machine hostname";
        };
        segment = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Segment this machine belongs to; defaults to my.router.primarySegment";
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

    dnsProfileSubmodule = types.submodule {
      options = {
        blocklistSources = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Blocky denylist sources for this DNS profile (URLs, file paths, or inline multiline strings).";
        };
        allowlistSources = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Reserved for future per-profile allowlist sources.";
        };
        denyDomains = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Inline domains or wildcard entries to block for this profile.";
        };
        allowDomains = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Reserved for future inline allow-domain overrides.";
        };
      };
    };

    segmentSubmodule = types.submodule ({name, ...}: {
      options = {
        description = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Optional human description for this segment";
        };

        vlan.id = mkOption {
          type = types.int;
          description = "802.1Q VLAN ID for this segment";
        };

        subnet = mkOption {
          type = types.str;
          description = "IPv4 subnet base without CIDR (e.g. 10.0.30)";
        };

        cidrPrefix = mkOption {
          type = types.int;
          default = 24;
          description = "CIDR prefix length for the subnet";
        };

        dhcp = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable DHCP service for this segment";
          };
          range = {
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
          reservations = mkOption {
            type = types.listOf reservationSubmodule;
            default = [];
            description = "Static DHCP reservations declared directly on the segment";
          };
          domainName = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Optional DHCP domain for this segment; defaults to my.router.dhcp.domainName";
          };
        };

        dns.profile = mkOption {
          type = types.str;
          default = "default";
          description = "Reserved for future per-segment DNS policy selection";
        };

        policy = {
          internet = mkOption {
            type = types.bool;
            default = true;
            description = "Allow this segment to reach WAN";
          };
          isolateClients = mkOption {
            type = types.bool;
            default = false;
            description = "Block forwarding between clients within the same segment";
          };
          routerAccessLevel = mkOption {
            type = types.nullOr (types.enum ["none" "infra" "full"]);
            default = null;
            description = "Router-host access profile; defaults to full for the primary segment and infra for others";
          };
          routerAllowedTcpPorts = mkOption {
            type = types.listOf types.int;
            default = [];
            description = "Additional router TCP ports reachable from this segment when routerAccessLevel is not full";
          };
          routerAllowedUdpPorts = mkOption {
            type = types.listOf types.int;
            default = [];
            description = "Additional router UDP ports reachable from this segment when routerAccessLevel is not full";
          };
          canReach = mkOption {
            type = types.listOf (types.oneOf [types.str reachRuleSubmodule]);
            default = [];
            description = "Segments or special zones this segment may reach";
          };
          canBeReachedFrom = mkOption {
            type = types.listOf (types.oneOf [types.str reachRuleSubmodule]);
            default = [];
            description = "Reverse rules allowing named segments or special zones to initiate traffic into this segment";
          };
        };
      };
    });

    portSubmodule = types.submodule {
      options = {
        mode = mkOption {
          type = types.enum ["trunk" "access"];
          default = "trunk";
          description = "Bridge port mode";
        };
        nativeSegment = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Native/untagged segment for trunk ports";
        };
        taggedSegments = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Tagged segments allowed on trunk ports";
        };
        accessSegment = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Single untagged segment for access ports";
        };
      };
    };

    normalizeReachRule = rule:
      if builtins.isString rule
      then {
        segment = rule;
        all = true;
        icmp = true;
        tcpPorts = [];
        udpPorts = [];
      }
      else {
        segment = rule.segment;
        all = rule.all;
        icmp = rule.icmp;
        tcpPorts = unique rule.tcpPorts;
        udpPorts = unique rule.udpPorts;
      };
  in {
    options = {
      my.router = {
        enable = mkEnableOption "Enable router functionality";

        hostname = mkOption {
          type = types.str;
          description = "Router hostname";
        };

        primarySegment = mkOption {
          type = types.str;
          default = "trusted";
          description = "Primary internal segment used for router identity, IPv6 ULA, and defaults";
        };

        ports = mkOption {
          type = types.attrsOf portSubmodule;
          default = {};
          description = "Bridge-facing router ports and their VLAN membership";
        };

        segments = mkOption {
          type = types.attrsOf segmentSubmodule;
          default = {};
          description = "Named routed network segments";
        };

        wan = {
          interface = mkOption {
            type = types.str;
            default = "enp1s0";
            description = "WAN interface name";
          };
          allowedTcpPorts = mkOption {
            type = types.listOf types.int;
            default = [];
            description = "Additional TCP ports to allow from WAN to the router";
          };
          allowedUdpPorts = mkOption {
            type = types.listOf types.int;
            default = [];
            description = "Additional UDP ports to allow from WAN to the router";
          };
        };

        ipv6.ulaPrefix = mkOption {
          type = types.str;
          default = "fd00:711a:edcd:7e75";
          description = "ULA prefix for IPv6 on the primary segment";
        };

        machines = mkOption {
          type = types.listOf machineSubmodule;
          default = [];
          description = "List of machines with static IPs and optional port forwarding";
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
            description = "Default domain name for DHCP clients";
          };
        };

        dns = {
          enable = mkEnableOption "Enable router DNS stack";
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
          profiles = mkOption {
            type = types.attrsOf dnsProfileSubmodule;
            default = {
              default = {};
            };
            description = "Per-segment DNS filtering profiles rendered into Blocky client groups.";
          };
          blocking = {
            blockType = mkOption {
              type = types.str;
              default = "zeroIp";
              description = "Global Blocky block type, for example zeroIp or nxDomain.";
            };
            blockTTL = mkOption {
              type = types.str;
              default = "6h";
              description = "TTL for blocked DNS responses.";
            };
            loadingStrategy = mkOption {
              type = types.enum ["blocking" "failOnError" "fast"];
              default = "blocking";
              description = "How Blocky initializes block/allow lists.";
            };
            refreshPeriod = mkOption {
              type = types.str;
              default = "24h";
              description = "Refresh interval for downloaded DNS blocklists.";
            };
          };
          enforcement = {
            redirectPort53 = mkOption {
              type = types.bool;
              default = true;
              description = "Redirect outbound DNS from non-exempt segments to the router DNS frontend.";
            };
            exemptSegments = mkOption {
              type = types.listOf types.str;
              default = [];
              description = "Segments exempt from forced DNS redirection.";
            };
          };
          dohBlocking = {
            enable = mkOption {
              type = types.bool;
              default = true;
              description = "Block known public encrypted-DNS endpoints and transports for non-exempt segments.";
            };
            exemptSegments = mkOption {
              type = types.listOf types.str;
              default = [];
              description = "Segments exempt from DoH/DoT/DoQ blocking; trusted should usually live here.";
            };
            denyDomains = mkOption {
              type = types.listOf types.str;
              default = [
                "cloudflare-dns.com"
                "mozilla.cloudflare-dns.com"
                "dns.google"
                "dns.quad9.net"
                "dns10.quad9.net"
                "dns11.quad9.net"
                "dns.nextdns.io"
                "dns.adguard-dns.com"
              ];
              description = "Known public DoH hostnames to block via DNS for protected segments.";
            };
            blockTcpPorts = mkOption {
              type = types.listOf types.int;
              default = [853];
              description = "Encrypted DNS TCP ports to block for protected segments.";
            };
            blockUdpPorts = mkOption {
              type = types.listOf types.int;
              default = [853 784 8853];
              description = "Encrypted DNS UDP ports to block for protected segments.";
            };
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
                  description = "Restrict access to internal routed networks using nginx ACLs";
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
              type = types.nullOr types.str;
              default = null;
              description = "Address to bind Netdata to; defaults to the primary segment gateway";
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
              default = [];
              description = "Interfaces to monitor; defaults to the bridge plus WAN";
            };
          };
          grafana = {
            enable = mkEnableOption "Enable Grafana dashboard";
            httpAddr = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Grafana HTTP bind address; defaults to the primary segment gateway";
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
                {
                  job_name = "blocky";
                  static_configs = [{targets = ["127.0.0.1:${toString 4000}"];}];
                  metrics_path = "/metrics";
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
            description = "Add route/forwarding between VPN and the primary segment";
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
                  description = "DNS server to place in generated peer config; defaults to router primary gateway.";
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
            description = "Default DNS for generated peer configs; defaults to the primary segment gateway.";
          };
        };
      };

      routerHelpers = mkOption {
        type = types.attrs;
        default = {};
        internal = true;
        description = "Derived helper values for router submodules";
      };
    };

    config = lib.mkIf cfg.enable {
      assertions = let
        segmentNames = attrNames cfg.segments;
        machineSegments = map (m: if m.segment != null then m.segment else cfg.primarySegment) cfg.machines;
        normalizedPolicyTargets = segmentNames ++ reservedZoneNames;
        allReachRules = concatMap (
          seg: map normalizeReachRule (seg.policy.canReach ++ seg.policy.canBeReachedFrom)
        ) (builtins.attrValues cfg.segments);
        allReservationIps = concatMap (
          name: let
            segment = cfg.segments.${name};
            directReservations = map (r: "${segment.subnet}.${r.ip}") segment.dhcp.reservations;
            machineReservations = map (m: "${segment.subnet}.${m.ip}") (filter (machine: (if machine.segment != null then machine.segment else cfg.primarySegment) == name) cfg.machines);
          in directReservations ++ machineReservations
        ) segmentNames;
        allReservationMacs =
          (map (m: m.mac) cfg.machines)
          ++ concatMap (name: map (r: r.mac) cfg.segments.${name}.dhcp.reservations) segmentNames;
      in [
        {
          assertion = cfg.ports != {};
          message = "my.router.ports must declare at least one bridge-facing port";
        }
        {
          assertion = hasAttr cfg.primarySegment cfg.segments;
          message = "my.router.primarySegment must refer to a declared segment";
        }
        {
          assertion = !(lib.elem cfg.primarySegment reservedZoneNames);
          message = "my.router.primarySegment must not use a reserved special-zone name";
        }
        {
          assertion = !(lib.elem cfg.wan.interface (attrNames cfg.ports));
          message = "my.router.wan.interface must not also be declared under my.router.ports";
        }
        {
          assertion = all (port: port >= 1 && port <= 65535) cfg.wan.allowedTcpPorts;
          message = "my.router.wan.allowedTcpPorts must only contain ports in range 1..65535";
        }
        {
          assertion = all (port: port >= 1 && port <= 65535) cfg.wan.allowedUdpPorts;
          message = "my.router.wan.allowedUdpPorts must only contain ports in range 1..65535";
        }
        {
          assertion = (lib.length segmentNames) == (lib.length (unique (map (name: cfg.segments.${name}.vlan.id) segmentNames)));
          message = "my.router.segments.*.vlan.id must be unique";
        }
        {
          assertion = (lib.length segmentNames) == (lib.length (unique (map (name: cfg.segments.${name}.subnet) segmentNames)));
          message = "my.router.segments.*.subnet must be unique";
        }
        {
          assertion = all (name: !(lib.elem name reservedZoneNames)) segmentNames;
          message = "my.router.segments must not use reserved names: wan, wireguard, cni, libvirt";
        }
        {
          assertion = all (name: cfg.segments.${name}.vlan.id >= 1 && cfg.segments.${name}.vlan.id <= 4094) segmentNames;
          message = "my.router.segments.*.vlan.id must be in range 1..4094";
        }
        {
          assertion = all (name: isIPv4Base cfg.segments.${name}.subnet) segmentNames;
          message = "my.router.segments.*.subnet must be an IPv4 base like 10.0.30";
        }
        {
          assertion = all (
            name:
              let
                segment = cfg.segments.${name};
              in
                segment.dhcp.range.start >= 2
                && segment.dhcp.range.end <= 254
                && segment.dhcp.range.start <= segment.dhcp.range.end
          ) segmentNames;
          message = "my.router.segments.*.dhcp.range must be within 2..254 and start <= end";
        }
        {
          assertion = all (
            port:
              if port.mode == "trunk"
              then port.nativeSegment != null && port.accessSegment == null && !(lib.elem port.nativeSegment port.taggedSegments) && (lib.length port.taggedSegments) == (lib.length (unique port.taggedSegments))
              else port.accessSegment != null && port.nativeSegment == null && port.taggedSegments == []
          ) (builtins.attrValues cfg.ports);
          message = "Router ports must be well-formed: trunk ports need nativeSegment only, access ports need accessSegment only";
        }
        {
          assertion = all (
            port:
              let
                refs =
                  if port.mode == "trunk"
                  then [port.nativeSegment] ++ port.taggedSegments
                  else [port.accessSegment];
              in
                all (segmentName: segmentName != null && hasAttr segmentName cfg.segments) refs
          ) (builtins.attrValues cfg.ports);
          message = "Router ports must only reference declared segments";
        }
        {
          assertion = (lib.length cfg.machines) == (lib.length (unique (map (m: m.name) cfg.machines)));
          message = "my.router.machines names must be unique";
        }
        {
          assertion = (lib.length allReservationMacs) == (lib.length (unique allReservationMacs));
          message = "Router machine and reservation MAC addresses must be unique";
        }
        {
          assertion = all (m: isHostOctet m.ip) cfg.machines;
          message = "my.router.machines.*.ip must be a numeric host octet in the range 2..254";
        }
        {
          assertion = all (segmentName: hasAttr segmentName cfg.segments) machineSegments;
          message = "my.router.machines.*.segment must refer to a declared segment";
        }
        {
          assertion = (lib.length allReservationIps) == (lib.length (unique allReservationIps));
          message = "Router machine and reservation IPs must be unique across segments";
        }
        {
          assertion = all (m: all (pf: pf.port >= 1 && pf.port <= 65535) m.portForwards) cfg.machines;
          message = "my.router.machines.*.portForwards.*.port must be in range 1..65535";
        }
        {
          assertion = all (
            name: all (r: isHostOctet r.ip) cfg.segments.${name}.dhcp.reservations
          ) segmentNames;
          message = "my.router.segments.*.dhcp.reservations.*.ip must be a numeric host octet in the range 2..254";
        }
        {
          assertion = all (
            rule:
              lib.elem rule.segment normalizedPolicyTargets
              && all (port: port >= 1 && port <= 65535) (rule.tcpPorts ++ rule.udpPorts)
          ) allReachRules;
          message = "Segment policy rules must reference known segments/zones and only use ports in range 1..65535";
        }
        {
          assertion = all (
            name:
              let
                policy = cfg.segments.${name}.policy;
              in
                all (port: port >= 1 && port <= 65535) (policy.routerAllowedTcpPorts ++ policy.routerAllowedUdpPorts)
          ) segmentNames;
          message = "my.router.segments.*.policy.routerAllowed{Tcp,Udp}Ports must be within 1..65535";
        }
        {
          assertion = lib.hasAttr "default" cfg.dns.profiles;
          message = "my.router.dns.profiles must define a default profile";
        }
        {
          assertion = all (name: lib.hasAttr cfg.segments.${name}.dns.profile cfg.dns.profiles) segmentNames;
          message = "my.router.segments.*.dns.profile must refer to a declared DNS profile";
        }
        {
          assertion = all (name: lib.hasAttr name cfg.segments) cfg.dns.enforcement.exemptSegments;
          message = "my.router.dns.enforcement.exemptSegments must only reference declared segments";
        }
        {
          assertion = all (name: lib.hasAttr name cfg.segments) cfg.dns.dohBlocking.exemptSegments;
          message = "my.router.dns.dohBlocking.exemptSegments must only reference declared segments";
        }
        {
          assertion = all (port: port >= 1 && port <= 65535) (cfg.dns.dohBlocking.blockTcpPorts ++ cfg.dns.dohBlocking.blockUdpPorts);
          message = "my.router.dns.dohBlocking.block{Tcp,Udp}Ports must only contain ports in range 1..65535";
        }
      ];

      routerHelpers = let
        segmentNames = attrNames cfg.segments;
        orderedSegmentNames = [cfg.primarySegment] ++ filter (name: name != cfg.primarySegment) segmentNames;
        lanBridge = "br-lan";
        wgCfg = cfg.wireguard or {};
        wgRouteToPrimary = wgCfg.routeToLan or true;
        wgSubnet = wgCfg.subnet or "10.6.0";
        wgCidr = "${wgSubnet}.0/${toString (wgCfg.cidrPrefix or 24)}";

        machineHelpers = map (
          machine: let
            segmentName = if machine.segment != null then machine.segment else cfg.primarySegment;
            segment = cfg.segments.${segmentName};
          in
            machine
            // {
              segment = segmentName;
              fullIp = "${segment.subnet}.${machine.ip}";
              subnet = segment.subnet;
            }
        ) cfg.machines;

        machineMap = listToAttrs (map (machine: nameValuePair machine.name machine) machineHelpers);

        mkSegment = name: let
          segment = cfg.segments.${name};
          machineReservations = map (
            machine: {
              inherit (machine) name mac;
              ip = machine.fullIp;
            }
          ) (filter (machine: machine.segment == name) machineHelpers);
          directReservations = map (
            reservation: {
              inherit (reservation) name mac;
              ip = "${segment.subnet}.${reservation.ip}";
            }
          ) segment.dhcp.reservations;
          routerAccessLevel =
            if segment.policy.routerAccessLevel != null
            then segment.policy.routerAccessLevel
            else if name == cfg.primarySegment then "full" else "infra";
          implicitCanReach =
            optionals (name == cfg.primarySegment && wgRouteToPrimary && (wgCfg.enable or false)) ["wireguard"]
            ++ optional (name == cfg.primarySegment) "libvirt";
        in {
          inherit name;
          description = segment.description;
          kind = "segment";
          vlanId = segment.vlan.id;
          subnet = segment.subnet;
          cidrPrefix = segment.cidrPrefix;
          subnetCidr = "${segment.subnet}.0/${toString segment.cidrPrefix}";
          subnets = ["${segment.subnet}.0/${toString segment.cidrPrefix}"];
          routerIp = "${segment.subnet}.1";
          interface = "vlan${toString segment.vlan.id}";
          internet = segment.policy.internet;
          isolateClients = segment.policy.isolateClients;
          routerAccessLevel = routerAccessLevel;
          routerAllowedTcpPorts = unique segment.policy.routerAllowedTcpPorts;
          routerAllowedUdpPorts = unique segment.policy.routerAllowedUdpPorts;
          reachRules = map normalizeReachRule (segment.policy.canReach ++ implicitCanReach);
          canBeReachedFrom = map normalizeReachRule segment.policy.canBeReachedFrom;
          dhcp = {
            enable = cfg.dhcp.enable && segment.dhcp.enable;
            domainName = if segment.dhcp.domainName != null then segment.dhcp.domainName else cfg.dhcp.domainName;
            poolStart = "${segment.subnet}.${toString segment.dhcp.range.start}";
            poolEnd = "${segment.subnet}.${toString segment.dhcp.range.end}";
            reservations = directReservations ++ machineReservations;
          };
          dnsProfile = segment.dns.profile;
          dnsRedirectEnabled = cfg.dns.enable && cfg.dns.enforcement.redirectPort53 && !(lib.elem name cfg.dns.enforcement.exemptSegments);
          isPrimary = name == cfg.primarySegment;
        };

        segmentMap = mapAttrs (name: _: mkSegment name) cfg.segments;
        orderedSegments = map (name: segmentMap.${name}) orderedSegmentNames;
        primarySegment = segmentMap.${cfg.primarySegment};

        portHelpers = mapAttrsToList (
          iface: port:
            port
            // {
              name = iface;
              memberships =
                if port.mode == "trunk"
                then [
                  {
                    VLAN = segmentMap.${port.nativeSegment}.vlanId;
                    PVID = segmentMap.${port.nativeSegment}.vlanId;
                    EgressUntagged = segmentMap.${port.nativeSegment}.vlanId;
                  }
                ] ++ map (segmentName: {VLAN = segmentMap.${segmentName}.vlanId;}) port.taggedSegments
                else [
                  {
                    VLAN = segmentMap.${port.accessSegment}.vlanId;
                    PVID = segmentMap.${port.accessSegment}.vlanId;
                    EgressUntagged = segmentMap.${port.accessSegment}.vlanId;
                  }
                ];
            }
        ) cfg.ports;

        wgZone = optional (wgCfg.enable or false) {
          name = "wireguard";
          kind = "wireguard";
          interface = wgCfg.interfaceName or "wg0";
          subnets = [wgCidr];
          routerIp = "${wgSubnet}.1";
          internet = true;
          isolateClients = false;
          routerAccessLevel = "full";
          routerAllowedTcpPorts = [];
          routerAllowedUdpPorts = [];
          reachRules = map normalizeReachRule ((optionals wgRouteToPrimary [cfg.primarySegment]) ++ ["cni"]);
          canBeReachedFrom = [];
          dhcp.enable = false;
        };

        cniZone = optional (config.systemd.network.enable or false) {
          name = "cni";
          kind = "cni";
          interface = "cni0";
          subnets = [];
          routerIp = null;
          internet = true;
          isolateClients = false;
          routerAccessLevel = "full";
          routerAllowedTcpPorts = [];
          routerAllowedUdpPorts = [];
          reachRules = map normalizeReachRule ([cfg.primarySegment] ++ optional (wgCfg.enable or false) "wireguard");
          canBeReachedFrom = [];
          dhcp.enable = false;
        };

        libvirtZone = {
          name = "libvirt";
          kind = "libvirt";
          interface = "virbr*";
          subnets = [];
          routerIp = null;
          internet = true;
          isolateClients = false;
          routerAccessLevel = "full";
          routerAllowedTcpPorts = [];
          routerAllowedUdpPorts = [];
          reachRules = [];
          canBeReachedFrom = [];
          dhcp.enable = false;
        };

        wanZone = {
          name = "wan";
          kind = "wan";
          interface = cfg.wan.interface;
          subnets = [];
          routerIp = null;
          internet = false;
          isolateClients = false;
          routerAccessLevel = "none";
          routerAllowedTcpPorts = [];
          routerAllowedUdpPorts = [];
          reachRules = [];
          canBeReachedFrom = [];
          dhcp.enable = false;
        };
      in {
        primarySegmentName = cfg.primarySegment;
        primarySegment = primarySegment;
        primarySubnet = primarySegment.subnet;
        primaryCidr = primarySegment.subnetCidr;
        primaryRouterIp = primarySegment.routerIp;
        primaryInterface = primarySegment.interface;
        lanBridge = lanBridge;
        wanInterface = cfg.wan.interface;
        bridgePorts = portHelpers;
        segmentMap = segmentMap;
        segments = orderedSegments;
        machineMap = machineMap;
        machineList = machineHelpers;
        zones = orderedSegments ++ wgZone ++ cniZone ++ [libvirtZone] ++ [wanZone];
        ulaPrefix = cfg.ipv6.ulaPrefix;

        # Compatibility aliases for modules still transitioning internally.
        lanSubnet = primarySegment.subnet;
        lanCidr = primarySegment.subnetCidr;
        routerIp = primarySegment.routerIp;
        lanInterface = primarySegment.interface;
        lanPorts = map (port: port.name) portHelpers;
      };
    };
  };
}
