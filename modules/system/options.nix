{
  config.flake.nixosModules.options = {
    lib,
    config,
    pkgs,
    ...
  }: let
    inherit (lib) mkIf mkMerge mkOption types;

    enabledServices = lib.filterAttrs (_: exposure: exposure.enable) config.my.exposure.services;

    firewallEntries = lib.flatten (lib.mapAttrsToList (
        name: exposure:
          lib.optionals exposure.firewall.local.enable (map (port: {
              inherit name port;
              protocol = "tcp";
              inherit (exposure.firewall.local) allowedSources;
            })
            exposure.firewall.local.tcp
            ++ map (port: {
              inherit name port;
              protocol = "udp";
              inherit (exposure.firewall.local) allowedSources;
            })
            exposure.firewall.local.udp)
      )
      enabledServices);

    unrestrictedTcpPorts = map (entry: entry.port) (lib.filter (entry: entry.protocol == "tcp" && entry.allowedSources == []) firewallEntries);
    unrestrictedUdpPorts = map (entry: entry.port) (lib.filter (entry: entry.protocol == "udp" && entry.allowedSources == []) firewallEntries);
    restrictedEntries = lib.filter (entry: entry.allowedSources != []) firewallEntries;

    mkNftRule = entry: source:
      if builtins.match ".*:.*" source != null
      then "ip6 saddr ${source} ${entry.protocol} dport ${toString entry.port} accept"
      else "ip saddr ${source} ${entry.protocol} dport ${toString entry.port} accept";

    nftRestrictedRules =
      lib.concatMapStringsSep "\n" (entry: ''
        ${lib.concatMapStringsSep "\n" (mkNftRule entry) entry.allowedSources}
        ${entry.protocol} dport ${toString entry.port} drop
      '')
      restrictedEntries;

    mkIptablesRule = entry: source:
      if builtins.match ".*:.*" source != null
      then "${pkgs.iptables}/bin/ip6tables -A nixos-fw -p ${entry.protocol} -s ${source} --dport ${toString entry.port} -j ACCEPT"
      else "${pkgs.iptables}/bin/iptables -A nixos-fw -p ${entry.protocol} -s ${source} --dport ${toString entry.port} -j ACCEPT";

    iptablesRestrictedRules =
      lib.concatMapStringsSep "\n" (entry: ''
        ${lib.concatMapStringsSep "\n" (mkIptablesRule entry) entry.allowedSources}
        ${pkgs.iptables}/bin/iptables -A nixos-fw -p ${entry.protocol} --dport ${toString entry.port} -j DROP
        ${pkgs.iptables}/bin/ip6tables -A nixos-fw -p ${entry.protocol} --dport ${toString entry.port} -j DROP
      '')
      restrictedEntries;

    publicVhostViolations = lib.concatLists (lib.mapAttrsToList (
        serviceName: exposure:
          map (vhost: "${serviceName}: ${vhost.domain}")
          (lib.filter (vhost: !(vhost.lanOnly || vhost.public || vhost.cloudflareProxied)) exposure.http.virtualHosts)
      )
      enabledServices);

    noAcmeCloudflareViolations = lib.concatLists (lib.mapAttrsToList (
        serviceName: exposure:
          map (vhost: "${serviceName}: ${vhost.domain}")
          (lib.filter (vhost: vhost.noAcme && vhost.cloudflareProxied) exposure.http.virtualHosts)
      )
      enabledServices);

    basicAuthSubmodule = types.submodule {
      options = {
        realm = mkOption {
          type = types.str;
          default = "Restricted";
          description = "Authentication realm shown to users.";
        };
        htpasswdFile = mkOption {
          type = types.path;
          description = "Path to htpasswd file for basic authentication.";
        };
      };
    };

    basicAuthSecretSubmodule = types.submodule {
      options = {
        realm = mkOption {
          type = types.str;
          default = "Restricted";
          description = "Authentication realm shown to users.";
        };
        name = mkOption {
          type = types.str;
          description = "Clan vars secret name resolved by the importing router.";
        };
        file = mkOption {
          type = types.str;
          default = "htpasswd";
          description = "File inside the Clan vars secret.";
        };
      };
    };

    acmeDns01Submodule = types.submodule {
      options = {
        dnsProvider = mkOption {
          type = types.str;
          description = "lego DNS provider name.";
        };
        environmentFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Path to an EnvironmentFile exporting provider variables.";
        };
        group = mkOption {
          type = types.str;
          default = "nginx";
          description = "Group that should own read access to issued certificates.";
        };
      };
    };

    vhostSubmodule = types.submodule {
      options = {
        domain = mkOption {
          type = types.str;
          description = "Domain name for this virtual host.";
        };
        targetHost = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Override upstream host for this virtual host.";
        };
        targetPort = mkOption {
          type = types.nullOr types.port;
          default = null;
          description = "Override upstream port for this virtual host.";
        };
        targetScheme = mkOption {
          type = types.nullOr (types.enum ["http" "https"]);
          default = null;
          description = "Override upstream scheme for this virtual host.";
        };
        websockets = mkOption {
          type = types.bool;
          default = true;
          description = "Enable WebSocket support.";
        };
        extraConfig = mkOption {
          type = types.lines;
          default = "";
          description = "Extra nginx location configuration.";
        };
        lanOnly = mkOption {
          type = types.bool;
          default = false;
          description = "Restrict access to internal routed networks using nginx ACLs.";
        };
        public = mkOption {
          type = types.bool;
          default = false;
          description = "Explicitly mark this virtual host as intentionally public.";
        };
        cloudflareProxied = mkOption {
          type = types.bool;
          default = false;
          description = "Require requests to arrive through Cloudflare edge IPs. LAN/WireGuard access remains allowed.";
        };
        noAcme = mkOption {
          type = types.bool;
          default = false;
          description = "Disable ACME for this vhost.";
        };
        useWildcard = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Name of wildcard cert from router nginx wildcardCerts.";
        };
        acmeDns01 = mkOption {
          type = types.nullOr acmeDns01Submodule;
          default = null;
          description = "Per-vhost DNS-01 ACME settings.";
        };
        basicAuth = mkOption {
          type = types.nullOr basicAuthSubmodule;
          default = null;
          description = "Enable HTTP Basic Authentication for this vhost.";
        };
        basicAuthSecret = mkOption {
          type = types.nullOr basicAuthSecretSubmodule;
          default = null;
          description = "Request router-resolved HTTP Basic Authentication from a Clan vars secret.";
        };
        publishDns = mkOption {
          type = types.bool;
          default = true;
          description = "Publish a generated DNS record for this virtual host.";
        };
      };
    };

    dnsRecordSubmodule = types.submodule {
      options = {
        name = mkOption {
          type = types.str;
          description = "DNS record name.";
        };
        target = mkOption {
          type = types.str;
          description = "DNS record target IP or router machine name.";
        };
      };
    };

    inherit ((import ../../flake/lib/exposure-options.nix {inherit lib;})) mkStandardExposureOptions;
  in {
    options = {
      my = {
        mainUser = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "The username of the primary user for this system.";
          };
          extraSshKeys = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Additional SSH public keys for the main user.";
          };
        };
        listenNetworkAddress = lib.mkOption {
          type = lib.types.str;
          default = "0.0.0.0";
          description = "The network address to listen on.";
        };
        gui = {
          enable = lib.mkEnableOption "Enable GUI session management";
          session = lib.mkOption {
            type = lib.types.enum ["hyprland" "sway" "niri"];
            default = "sway";
            description = "The Wayland session type to use";
          };
          terminal = lib.mkOption {
            type = lib.types.enum ["kitty"];
            default = "kitty";
            description = "The terminal emulator to use in GUI sessions";
          };
          _terminalCommand = lib.mkOption {
            type = lib.types.str;
            default = "kitty";
            description = "The terminal emulator command";
          };
        };
        exposure = {
          localFirewall.enable = mkOption {
            type = types.bool;
            default = true;
            description = "Apply my.exposure.services.*.firewall.local rules to this host's firewall.";
          };

          routerImports = {
            machines = mkOption {
              type = types.listOf types.str;
              default = [];
              description = "Machine names whose router-enabled exposure services should be imported by this router.";
            };
            routerName = mkOption {
              type = types.str;
              default = config.networking.hostName or "";
              description = "Name this router uses when matching service router.targets.";
            };
            defaultDnsTarget = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Default DNS target for imported router exposure records. Null means derive the local router primary address.";
            };
            vhostOverrides = mkOption {
              type = types.attrsOf (types.submodule {
                options = {
                  basicAuth = mkOption {
                    type = types.nullOr basicAuthSubmodule;
                    default = null;
                    description = "Router-local Basic Auth override for imported vhosts.";
                  };
                };
              });
              default = {};
              description = "Router-local virtual host overrides keyed by '<machine>.<service>'. Prefer service-owned basicAuthSecret for Clan vars secrets.";
            };
          };

          services = mkOption {
            type = types.attrsOf (types.submodule ({name, ...}: {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable this exposure declaration.";
                };

                renderedFrom = mkOption {
                  type = types.nullOr (types.submodule {
                    options = {
                      machine = mkOption {type = types.str;};
                      service = mkOption {type = types.str;};
                    };
                  });
                  default = null;
                  description = "Source exposure imported and rendered by this router, if any.";
                };

                upstream = {
                  host = mkOption {
                    type = types.str;
                    default = config.my.listenNetworkAddress;
                    description = "Default upstream host used by generated reverse proxy entries.";
                  };
                  port = mkOption {
                    type = types.nullOr types.port;
                    default = null;
                    description = "Default upstream port used by generated reverse proxy entries.";
                  };
                  scheme = mkOption {
                    type = types.enum ["http" "https"];
                    default = "http";
                    description = "Default upstream scheme used by generated reverse proxy entries.";
                  };
                };

                http.virtualHosts = mkOption {
                  type = types.listOf vhostSubmodule;
                  default = [];
                  description = "Reverse proxy virtual hosts requested by this service.";
                };

                dns.records = mkOption {
                  type = types.listOf dnsRecordSubmodule;
                  default = [];
                  description = "DNS records requested by this service.";
                };

                router = {
                  enable = mkOption {
                    type = types.bool;
                    default = false;
                    description = "Export this service for router-side reverse proxy/DNS aggregation.";
                  };
                  targetHost = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                    description = "Router-reachable upstream host. Defaults to the source machine name when imported by a router.";
                  };
                  targets = mkOption {
                    type = types.listOf types.str;
                    default = [];
                    description = "Router names allowed to import this exposure. Empty means any importing router may import it.";
                  };
                  dnsTarget = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                    description = "DNS target to publish from the router. Defaults to the importing router address.";
                  };
                };

                firewall.local = {
                  enable = mkOption {
                    type = types.bool;
                    default = false;
                    description = "Open service ports on the local host firewall.";
                  };
                  tcp = mkOption {
                    type = types.listOf types.port;
                    default = [];
                    description = "TCP ports to open on the local host.";
                  };
                  udp = mkOption {
                    type = types.listOf types.port;
                    default = [];
                    description = "UDP ports to open on the local host.";
                  };
                  allowedSources = mkOption {
                    type = types.listOf types.str;
                    default = [];
                    description = "Source IPs/CIDRs allowed to access local firewall ports. Empty means unrestricted.";
                  };
                };
              };

              config = {
                _module.args.exposureName = name;
              };
            }));
            default = {};
            description = "Service-owned network exposure declarations.";
          };
        };
      };
    };

    config = mkMerge [
      {
        _module.args.mkStandardExposureOptions = mkStandardExposureOptions;
      }
      {
        my.gui._terminalCommand =
          if config.my.gui.terminal == "kitty"
          then "${pkgs.kitty}/bin/kitty"
          else "${pkgs.kitty}/bin/kitty";

        # Required by vpn-confinement module (accessed at top level before networking module loads)
        networking.enableIPv6 = true;

        assertions = [
          {
            assertion = publicVhostViolations == [];
            message = "Exposure vhosts must set either lanOnly = true or public = true or cloudflareProxied = true: ${lib.concatStringsSep ", " publicVhostViolations}";
          }
          {
            assertion = noAcmeCloudflareViolations == [];
            message = "Exposure vhosts with cloudflareProxied = true must not set noAcme = true (HTTPS must be served): ${lib.concatStringsSep ", " noAcmeCloudflareViolations}";
          }
        ];
      }
      (mkIf config.my.exposure.localFirewall.enable (mkMerge [
        {
          networking.firewall.allowedTCPPorts = unrestrictedTcpPorts;
          networking.firewall.allowedUDPPorts = unrestrictedUdpPorts;
        }
        (mkIf (restrictedEntries != []) {
          networking.firewall.extraInputRules = lib.mkAfter nftRestrictedRules;
          networking.firewall.extraCommands = mkIf (!config.networking.nftables.enable) (lib.mkAfter iptablesRestrictedRules);
        })
      ]))
    ];
  };
}
