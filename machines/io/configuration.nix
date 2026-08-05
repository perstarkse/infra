{
  ctx,
  config,
  lib,
  pkgs,
  ...
}: let
  endpointsLib = ctx.flake.lib.endpoints or (import ../../flake/lib/endpoints.nix {inherit (pkgs) lib;});
  keepAwakeIdentityFile = config.my.secrets.getPath "wake-proxy-keep-awake-ssh" "private_key";
  routerImportCfg = config.my.endpoints.imports;
  routerDefaultDnsTarget =
    if routerImportCfg.defaultDnsTarget != null
    then routerImportCfg.defaultDnsTarget
    else config.routerHelpers.primarySegment.routerIp;
  routerImportedEndpoints = endpointsLib.mkRouterImportedEndpoints {
    nixosConfigurations = ctx.flake.nixosConfigurations or {};
    inherit routerImportCfg;
    defaultDnsTarget = routerDefaultDnsTarget;
    routerName = "io";
    resolveBasicAuthSecret = secret: {
      inherit (secret) realm;
      htpasswdFile = config.my.secrets.getPath secret.name secret.file;
    };
  };
in {
  clan.core.deployment.requireExplicitUpdate = true;

  imports = with ctx.flake.nixosModules;
    [
      ./hardware-configuration.nix
      ./boot.nix
      ./agent-microvm.nix
      interception-tools
      stylix
      shared
      options
      attic-cache
      router
      wake-proxy
      webdav-htpasswd-secret
      heartbeat
      home-assistant
      ntfy
      unifi-os
      frigate
      garage
      atuin
      libvirt
      agent-microvm
    ]
    ++ (with ctx.inputs.varsHelper.nixosModules; [default]);

  services.wakeproxy = {
    enable = true;
    listenAddress = "10.0.0.1";
    port = 8091;

    upstreamHost = "10.0.0.15";
    upstreamPort = 8504;
    healthPath = "/api/pi-web/version";

    wolMac = "f0:2f:74:de:91:0a";
    wolBroadcastIp = "10.0.0.255";
    wolBroadcastPort = 9;

    wakeTimeout = 180;
    pollInterval = 2;
    wakePollIntervalMs = 2000;
    readyCacheTtl = 5;
    trustProxyHeaders = true;
    trustedProxyIps = [
      "127.0.0.1"
      "::1"
      "10.0.0.1"
    ];
    externalOrigin = "https://wake.stark.pub";
    passwordHashFile = config.my.secrets.getPath "wake-proxy" "env";
    keepAwake = {
      maxDurationSeconds = 14400;
      remoteSsh =
        {
          host = "10.0.0.15";
        }
        // lib.optionalAttrs (keepAwakeIdentityFile != null) {
          identityFile = keepAwakeIdentityFile;
        };
    };
  };

  my = {
    wake-proxy.endpoints = {
      enable = true;
      domain = "wake.stark.pub";
      public = true;
      cloudflareProxied = true;
      acmeDns01 = {
        dnsProvider = "cloudflare";
        environmentFile = config.my.secrets.getPath "api-key-cloudflare-dns" "api-token";
      };
    };

    listenNetworkAddress = "10.0.0.1"; # Internal LAN IP

    # Public-domain registry is derived, not maintained (see options.nix):
    # every non-lanOnly vhost across the endpoints layer plus the explicit
    # non-vhost public records below. ddclient zones flow from the result.
    publicDnsRecords = [
      "wg.stark.pub" # WireGuard endpoint — public A record, no vhost
      "mail.stark.pub" # SMTP/IMAP on makemake — public A record, no nginx vhost
      "orebro.politikerstod.stark.pub" # parked politikerstod instance — public A record, no vhost
    ];

    attic-cache.client = {
      enable = true;
      endpoint = "http://10.0.0.10:8092";
      serverName = "makemake";
      cacheName = "heliosphere";
    };

    mainUser = {
      enable = false;
      name = "p";
    };

    frigate.enable = true;
    home-assistant.enable = true;

    # Garage S3-compatible storage (clustered with makemake)
    garage = {
      enable = true;
      dataDir = "/storage/garage/data";
      metaDir = "/storage/garage/meta";
      replicationMode = 2;
      rpcPublicAddr = "10.0.0.1:3901";
      zone = "io";
    };

    atuin = {
      enable = true;
      syncAddress = "http://10.0.0.10:8888";
    };

    heartbeat.push = {
      enable = true;
      schedule = "*:0/5";
      # sedna's heartbeat receiver over the public internet (port 18080 opened
      # in sedna's WAN firewall). Previously a ZeroTier IPv6 literal that
      # silently died if sedna's ZT address changed.
      endpointUrl = "http://130.61.55.4:18080/heartbeat";
    };

    frigate.endpoints = {
      enable = true;
      domain = "frigate.lan.stark.pub";
      useWildcard = "lanstark";
    };

    home-assistant.endpoints = {
      enable = true;
      domain = "home.lan.stark.pub";
      useWildcard = "lanstark";
    };

    ntfy = {
      enable = true;
      address = "10.0.0.1";
      baseUrl = "https://ntfy.lan.stark.pub";
      secretName = "ntfy";
      endpoints = {
        enable = true;
        useWildcard = "lanstark";
      };
      settings = {
        behind-proxy = true;
        upstream-base-url = "https://ntfy.sh";
      };
    };

    endpoints.imports = {
      machines = ["makemake"];
      routerName = "io";
      vhostOverrides."makemake.nous" = {
        acmeDns01 = {
          dnsProvider = "cloudflare";
          environmentFile = config.my.secrets.getPath "api-key-cloudflare-dns" "api-token";
        };
      };
    };

    endpoints.services =
      routerImportedEndpoints
      // {
        unifi-router = {
          upstream = {
            host = "10.0.0.21";
            port = 443;
            scheme = "https";
          };
          http.virtualHosts = [
            {
              domain = "unifi.lan.stark.pub";
              lanOnly = true;
              useWildcard = "lanstark";
            }
          ];
          dns.records = [
            {
              name = "unifi.lan.stark.pub";
              target = "10.0.0.1";
            }
          ];
        };
        # invoices.stark.pub — public webhook endpoint for Accounted
        # invoice-inbox (migrated from raw services.nginx.virtualHosts). Only
        # the Resend inbound email webhook path proxies to accounted on
        # makemake; everything else returns 444 like the `_` default server.
        invoices = {
          upstream = {
            host = "10.0.0.10";
            port = 3050;
          };
          http.virtualHosts = [
            {
              domain = "invoices.stark.pub";
              public = true;
              websockets = false;
              acmeDns01 = {
                dnsProvider = "cloudflare";
                environmentFile = config.my.secrets.getPath "api-key-cloudflare-dns" "api-token";
              };
              extraConfig = ''
                if ($uri !~ ^/api/extensions/ext/invoice-inbox/inbound) {
                  return 444;
                }
              '';
            }
          ];
        };
      };

    secrets = {
      discover = {
        enable = true;
        includeTags = ["ddclient" "cloudflare" "wireguard" "router" "garage" "wake-proxy" "keep-awake" "heartbeat" "ntfy" "attic-cache" "journal-upload" "frigate"];
      };

      allowReadAccess = [
        {
          readers = ["wake-proxy"];
          path = config.my.secrets.getPath "wake-proxy" "env";
        }
        {
          readers = ["nginx"];
          path = config.my.secrets.getPath "webdav-htpasswd" "htpasswd";
        }
      ];
    };

    router = {
      enable = true;
      hostname = "io";
      primarySegment = "trusted";
      ports = {
        enp2s0 = {
          mode = "trunk";
          nativeSegment = "trusted";
          taggedSegments = ["iot" "work" "kids" "guests" "cameras"];
        };
        enp3s0 = {
          mode = "trunk";
          nativeSegment = "trusted";
          taggedSegments = ["iot" "work" "kids" "guests" "cameras"];
        };
        enp4s0 = {
          mode = "trunk";
          nativeSegment = "trusted";
          taggedSegments = ["iot" "work" "kids" "guests" "cameras"];
        };
      };
      segments = {
        trusted = {
          vlan.id = 1;
          subnet = "10.0.0";
          dhcp = {
            range = {
              start = 100;
              end = 200;
            };
          };
          policy.routerAllowedTcpPorts = [3900 3901];
        };
        iot = {
          vlan.id = 20;
          subnet = "10.0.20";
          dns.profile = "iot";
          policy = {
            canBeReachedFrom = [
              {
                segment = "trusted";
                tcpPorts = [8008 8009 8443];
                udpPorts = [1900 5353];
              }
            ];
          };
        };

        work = {
          vlan.id = 60;
          subnet = "10.0.60";
          policy = {
            tcpMssClamp = 1280;
          };
        };

        kids = {
          vlan.id = 40;
          subnet = "10.0.40";
          dns.profile = "kids";
        };

        guests = {
          vlan.id = 50;
          subnet = "10.0.50";
          dns.profile = "guests";
          policy = {
            isolateClients = true;
          };
        };

        cameras = {
          vlan.id = 30;
          subnet = "10.0.30";
          dhcp = {
            range = {
              start = 10;
              end = 50;
            };
            reservations = [
              {
                name = "reolink-p330";
                ip = "10";
                mac = "ec:71:db:01:64:fd";
              }
            ];
          };
          policy = {
            internet = false;
          };
        };
      };
      wan = {
        allowedUdpPorts =
          if config.services.zerotierone.enable
          then [config.services.zerotierone.port]
          else [];
      };

      zerotier = {
        enable = true;
      };

      wireguard = {
        enable = true;
        defaultEndpoint = "wg.stark.pub:51820";
        peers = [
          {
            name = "pfone";
            ip = 2;
            autoGenerate = true;
            persistentKeepalive = 25;
          }
        ];
      };

      machines = [
        {
          name = "charon";
          ip = "15";
          mac = "f0:2f:74:de:91:0a";
        }
        {
          name = "unifi-switch";
          ip = "20";
          mac = "84:78:48:6a:f9:f0";
        }
        {
          name = "ariel";
          ip = "25";
          mac = "a0:88:69:af:a7:f3";
        }
        {
          name = "makemake";
          ip = "10";
          mac = "00:d0:b4:02:bb:3c";
          portForwards = [
            {
              port = 25;
              protocol = "tcp";
            }
            {
              port = 465;
              protocol = "tcp";
            }
            {
              port = 993;
              protocol = "tcp";
            }
            {
              port = 32400;
              protocol = "tcp";
            }
          ];
        }
      ];

      services = [
        {
          name = "mail.stark.pub";
          target = "10.0.0.10";
        }
      ];

      dhcp = {
        enable = true;
        domainName = "lan.stark.pub";
      };

      dns = {
        enable = true;
        localZones = ["lan." "lan.stark.pub."];
        profiles = {
          iot = {
            blocklistSources = [
              "https://s3.amazonaws.com/lists.disconnect.me/simple_ad.txt"
              "https://s3.amazonaws.com/lists.disconnect.me/simple_tracking.txt"
            ];
          };
          guests = {
            blocklistSources = [
              "https://s3.amazonaws.com/lists.disconnect.me/simple_ad.txt"
              "https://s3.amazonaws.com/lists.disconnect.me/simple_tracking.txt"
              "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews/hosts"
            ];
          };
          kids = {
            blocklistSources = [
              "https://s3.amazonaws.com/lists.disconnect.me/simple_ad.txt"
              "https://s3.amazonaws.com/lists.disconnect.me/simple_tracking.txt"
              "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/native/tif.txt"
              "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/native/gambling.txt"
            ];
          };
        };
        profiles.default.denyDomains = ["use-application-dns.net"];
        filterAaaa = true;
        enforcement.exemptSegments = ["work"];
        dohBlocking.exemptSegments = ["work"];
      };

      nginx = {
        enable = true;
        # ddclient zones derived from my.publicDomains so the registry is the
        # only place a public domain is declared.
        ddclient = {
          enable = true;
          zones = lib.mapAttrsToList (zone: domains: {
            inherit zone domains;
            passwordFile = config.my.secrets.getPath "ddclient" "ddclient.conf";
          }) (lib.groupBy (d: config.my.publicDomains.${d}) (lib.attrNames config.my.publicDomains));
        };
        wildcardCerts = [
          {
            name = "lanstark";
            baseDomain = "lan.stark.pub";
            dnsProvider = "cloudflare";
            environmentFile = config.my.secrets.getPath "api-key-cloudflare-dns" "api-token";
            group = "nginx";
          }
        ];
        # Interactive SPA apps (minne, nous, politikerstod, request) declare
        # rateLimit = null on their vhosts (see the service modules); the
        # strict `public` limit_req zone applies to every other public vhost.
        virtualHosts = [];
      };

      casting = {
        enable = true;
        targetSegments = ["iot"];
      };

      security = {
        enable = true;
        fail2ban = {
          # LAN-fleet ban policy: 30m is a deliberate override of the 10m
          # module default (fail2ban restarts are cheap, 2am breakage is not).
          banTime = "30m";
        };
        journalReceiver.enable = true;
      };
    };

    libvirt = {
      enable = true;
    };
  };

  my.unifi-os = {
    enable = true;
    advertisedAddress = "10.0.0.21";
    network = {
      hostAccess = {
        enable = true;
        address = "10.0.0.22";
      };
    };
  };

  # Wildcard *.lan.stark.pub ACME renewal: the router's own resolver
  # (blocky→unbound, lan.stark.pub is a static local zone) answers NODATA for
  # _acme-challenge.lan.stark.pub, so lego's DNS-01 propagation check would
  # fail. Query public resolvers for the challenge TXT record instead.
  security.acme.certs."lan.stark.pub".extraLegoFlags = ["--dns.resolvers=1.1.1.1:53,1.0.0.1:53"];

  # Escape hatch: raw services.nginx.virtualHosts writes must not introduce
  # new WAN-listening vhosts outside the endpoints layer. Every public domain
  # flows through the derived my.publicDomains registry (ddclient zones), so a
  # raw public vhost would silently miss DDNS updates. Internal raw vhosts
  # (e.g. journal-upload, which binds 10.0.0.1) are unaffected.
  assertions = let
    declaredDomains = lib.unique (
      (lib.concatLists (lib.mapAttrsToList (_: e:
        map (v: v.domain) e.http.virtualHosts)
      (lib.filterAttrs (_: e: e.enable) config.my.endpoints.services)))
      ++ map (v: v.domain) config.my.router.nginx.virtualHosts
    );
    rawVhosts = lib.filterAttrs (name: _: name != "_" && !(lib.elem name declaredDomains)) config.services.nginx.virtualHosts;
    wanRawVhosts = lib.filterAttrs (_: v: lib.any (l: (l.addr or "") == "0.0.0.0") (v.listen or [])) rawVhosts;
  in [
    {
      assertion = wanRawVhosts == {};
      message = "Raw nginx vhosts bypassing the endpoints layer must not listen on WAN (0.0.0.0): ${lib.concatStringsSep ", " (lib.attrNames wanRawVhosts)}";
    }
  ];
}
