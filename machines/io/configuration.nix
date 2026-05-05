{
  ctx,
  config,
  lib,
  pkgs,
  ...
}: let
  exposureLib = ctx.flake.lib.exposure or (import ../../flake/lib/exposure.nix {inherit (pkgs) lib;});
  keepAwakeIdentityFile = config.my.secrets.getPath "wake-proxy-keep-awake-ssh" "private_key";
  routerImportCfg = config.my.exposure.routerImports;
  routerDefaultDnsTarget =
    if routerImportCfg.defaultDnsTarget != null
    then routerImportCfg.defaultDnsTarget
    else config.routerHelpers.primarySegment.routerIp or "10.0.0.1";
  routerImportedExposures = exposureLib.mkRouterImportedExposures {
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
      interception-tools
      system-stylix
      shared
      options
      attic-cache
      router
      wake-proxy
      heartbeat
      home-assistant
      ntfy
      unifi-os
      frigate
      garage
      atuin
      libvirt
      # oumu-vm
      # go2rtc
    ]
    ++ (with ctx.inputs.varsHelper.nixosModules; [default]);

  time.timeZone = "Europe/Stockholm";

  services.wakeproxy = {
    enable = true;
    listenAddress = "10.0.0.1";
    port = 8091;

    upstreamHost = "10.0.0.15";
    upstreamPort = 3000;
    healthPath = "/health";

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
    wake-proxy.exposure = {
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

    attic-cache.client = {
      enable = true;
      endpoint = "http://10.0.0.10:8092";
      serverName = "makemake";
      cacheName = "heliosphere";
    };

    mainUser = {
      name = "p";
    };

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

    heartbeat.push.enable = true;

    frigate.exposure = {
      enable = true;
      domain = "frigate.lan.stark.pub";
      useWildcard = "lanstark";
    };

    home-assistant.exposure = {
      enable = true;
      domain = "home.lan.stark.pub";
      useWildcard = "lanstark";
    };

    ntfy = {
      enable = true;
      address = "10.0.0.1";
      baseUrl = "https://ntfy.lan.stark.pub";
      secretName = "ntfy";
      exposure = {
        enable = true;
        useWildcard = "lanstark";
      };
      settings = {
        behind-proxy = true;
        upstream-base-url = "https://ntfy.sh";
      };
    };

    exposure.routerImports = {
      machines = ["makemake"];
      routerName = "io";
    };

    exposure.services =
      routerImportedExposures
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
      };

    secrets = {
      discover = {
        enable = true;
        dir = ../../vars/generators;
        includeTags = ["ddclient" "cloudflare" "wireguard" "router" "garage" "wake-proxy" "keep-awake" "heartbeat" "ntfy" "attic-cache"];
      };

      generateManifest = false;
      allowReadAccess = [
        {
          readers = ["wake-proxy"];
          path = config.my.secrets.getPath "wake-proxy" "env";
        }
        {
          readers = ["wake-proxy"];
          path = config.my.secrets.getPath "wake-proxy-keep-awake-ssh" "private_key";
        }
        {
          readers = ["systemd-network"];
          path = config.my.secrets.getPath "wireguard-server" "private-key";
        }
        {
          readers = ["nginx"];
          path = config.my.secrets.getPath "webdav-htpasswd" "htpasswd";
        }
      ];

      declarations = [
        (config.my.secrets.mkMachineSecret {
          name = "oumu-deploy-key";
          share = false;
          runtimeInputs = [pkgs.openssh];
          files = {
            private_key = {
              mode = "0400";
              owner = "root";
              neededFor = "services";
            };
            public_key = {
              mode = "0444";
              # secret = true; # Treat as secret to avoid store warning, but readable
            };
          };
          script = ''
            ssh-keygen -t ed25519 -C "oumu-vm-deploy-key" -f "$out/private_key" -N ""
            mv "$out/private_key.pub" "$out/public_key"
          '';
        })
        (config.my.secrets.mkMachineSecret {
          name = "webdav-htpasswd";
          share = true;
          runtimeInputs = [pkgs.apacheHttpd];
          files = {
            htpasswd = {mode = "0400";};
            password = {mode = "0400";};
          };
          script = ''
            username="webdav"
            password=$(head -c 24 /dev/urandom | base64 -w0 | tr -d '/+=')
            htpasswd -nbB "$username" "$password" > "$out/htpasswd"
            echo "$password" > "$out/password"
          '';
        })
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
          taggedSegments = ["iot" "kids" "guests" "cameras"];
        };
        enp3s0 = {
          mode = "trunk";
          nativeSegment = "trusted";
          taggedSegments = ["iot" "kids" "guests" "cameras"];
        };
        enp4s0 = {
          mode = "trunk";
          nativeSegment = "trusted";
          taggedSegments = ["iot" "kids" "guests" "cameras"];
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
          policy.routerAllowedTcpPorts = [3900 3901 3902];
        };
        iot = {
          vlan.id = 20;
          subnet = "10.0.20";
          dhcp = {
            range = {
              start = 10;
              end = 200;
            };
          };
          dns.profile = "iot";
          policy = {
            internet = true;
            isolateClients = false;
            canReach = [];
            canBeReachedFrom = [
              {
                segment = "trusted";
                tcpPorts = [8008 8009 8443];
                udpPorts = [1900 5353];
              }
            ];
          };
        };

        kids = {
          vlan.id = 40;
          subnet = "10.0.40";
          dhcp = {
            range = {
              start = 10;
              end = 200;
            };
          };
          dns.profile = "kids";
          policy = {
            internet = true;
            isolateClients = false;
            canReach = [];
          };
        };
        guests = {
          vlan.id = 50;
          subnet = "10.0.50";
          dhcp = {
            range = {
              start = 10;
              end = 200;
            };
          };
          dns.profile = "guests";
          policy = {
            internet = true;
            isolateClients = true;
            canReach = [];
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
            canReach = [];
          };
        };
      };
      wan = {
        interface = "enp1s0";
        allowedUdpPorts =
          if config.services.zerotierone.enable
          then [config.services.zerotierone.port]
          else [];
      };
      ipv6.ulaPrefix = "fd00:711a:edcd:7e75";

      wireguard = {
        enable = true;
        defaultEndpoint = "mail.stark.pub:51820";
        peers = [
          {
            name = "phone";
            ip = 2;
            autoGenerate = true;
            persistentKeepalive = 25;
          }
          {
            name = "bro";
            ip = 3;
            autoGenerate = true;
            persistentKeepalive = 25;
          }
          {
            name = "ariel";
            ip = 4;
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
          portForwards = [];
        }
        {
          name = "unifi-switch";
          ip = "20";
          mac = "84:78:48:6a:f9:f0";
          portForwards = [];
        }
        {
          name = "ariel";
          ip = "25";
          mac = "a0:88:69:af:a7:f3";
          portForwards = [];
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
        {
          name = "kube-test.lan.stark.pub";
          target = "10.0.0.1";
        }
      ];

      dhcp = {
        enable = true;
        validLifetime = 86400;
        renewTimer = 43200;
        rebindTimer = 75600;
        domainName = "lan.stark.pub";
      };

      dns = {
        enable = true;
        localZones = ["lan." "lan.stark.pub."];
        upstreamServers = [
          "1.1.1.1@853#cloudflare-dns.com"
          "1.0.0.1@853#cloudflare-dns.com"
          "2606:4700:4700::1111@853#cloudflare-dns.com"
          "2606:4700:4700::1001@853#cloudflare-dns.com"
        ];
        profiles = {
          default = {};
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
        enforcement.exemptSegments = [];
        dohBlocking.exemptSegments = [];
      };

      nginx = {
        enable = true;
        acmeEmail = "services@stark.pub";
        ddclient = {
          enable = true;
          zones = [
            {
              zone = "stark.pub";
              domains = [
                "chat.stark.pub"
                "minne.stark.pub"
                "vault.stark.pub"
                "request.stark.pub"
                "encke.stark.pub"
                "minne-demo.stark.pub"
                "mail.stark.pub"
                "politikerstod.stark.pub"
                "wake.stark.pub"
              ];
              passwordFile = config.my.secrets.getPath "ddclient" "ddclient.conf";
            }
            {
              zone = "nous.fyi";
              domains = ["nous.fyi"];
              passwordFile = config.my.secrets.getPath "ddclient" "ddclient.conf";
            }
          ];
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
        virtualHosts = [
          {
            domain = "kube-test.lan.stark.pub";
            target = "10.0.0.10";
            port = 80;
            websockets = false;
            useWildcard = "lanstark";
          }
        ];
      };

      casting = {
        enable = true;
        sourceSegment = "trusted";
        targetSegments = ["iot"];
      };

      monitoring = {
        enable = false;
        grafana = {
          enable = true;
          httpAddr = "10.0.0.1";
          httpPort = 8888;
          dataDir = "/var/lib/grafana";
        };
        prometheus = {
          enable = true;
          port = 9990;
          exporters = {
            node = {
              enable = true;
              enabledCollectors = ["systemd"];
            };
            unbound.enable = true;
          };
          scrapeConfigs = [
            {
              job_name = "node";
              static_configs = [{targets = ["localhost:9100"];}];
            }
            {
              job_name = "unbound";
              static_configs = [{targets = ["localhost:9167"];}];
            }
            {
              job_name = "blocky";
              static_configs = [{targets = ["127.0.0.1:4000"];}];
              metrics_path = "/metrics";
            }
          ];
        };
        netdata.enable = false;
        ntopng.enable = false;
      };

      security = {
        enable = true;
        fail2ban = {
          enable = true;
          banTime = "30m";
          maxRetry = 5;
          jails = {
            sshd.enable = true;
            nginx = {
              urlProbe.enable = true;
              botsearch.enable = true;
            };
            mail = {
              postfix.enable = true;
              dovecot.enable = true;
            };
          };
        };
        journalReceiver.enable = true;
      };
    };

    # Libvirt for VM hosting
    libvirtd = {
      enable = true;
    };

    # # Oumu AI assistant VM (interstellar visitor)
    # oumu-vm = {
    #   enable = true;
    #   storageBaseDir = "/storage/libvirt/oumu";
    #   memoryGb = 4;
    #   diskSizeGb = 120;
    # };
  };

  services.unifi-os-server = {
    enable = true;
    advertisedAddress = "10.0.0.21";
    network = {
      hostAccess = {
        enable = true;
        address = "10.0.0.22";
      };
    };
  };

  # Custom nginx location for nous.fyi /app/ -> /assets/app/ rewrite
  services.nginx.virtualHosts."nous.fyi".locations = {
    "/app/" = {
      proxyPass = "http://10.0.0.10:3002/assets/app/";
      recommendedProxySettings = true;
      extraConfig = ''
        client_max_body_size 55M;
        if ($cf_access_ok = 0) { return 403; }
      '';
    };
  };
}
