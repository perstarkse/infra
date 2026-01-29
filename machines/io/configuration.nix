{
  modules,
  config,
  vars-helper,
  pkgs,
  ...
}: {
  imports = with modules.nixosModules;
    [
      ./hardware-configuration.nix
      ./boot.nix
      interception-tools
      system-stylix
      shared
      options
      router
      home-assistant
      k3s
      unifi-controller
      frigate
      garage
      atuin
      # go2rtc
    ]
    ++ (with vars-helper.nixosModules; [default]);

  time.timeZone = "Europe/Stockholm";
  nixpkgs.config.allowUnfree = true;

  my = {
    listenNetworkAddress = "10.0.0.1"; # Internal LAN IP

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

    secrets.discover = {
      enable = true;
      dir = ../../vars/generators;
      includeTags = ["ddclient" "k3s" "cloudflare" "wireguard" "router" "garage"];
    };

    secrets.generateManifest = false;
    secrets.allowReadAccess = [
      {
        readers = ["systemd-network"];
        path = config.my.secrets.getPath "wireguard-server" "private-key";
      }
      {
        readers = ["nginx"];
        path = config.my.secrets.getPath "webdav-htpasswd" "htpasswd";
      }
    ];

    secrets.declarations = [
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

    router = {
      enable = true;
      hostname = "io";
      lan = {
        subnet = "10.0.0";
        dhcpRange = {
          start = 100;
          end = 200;
        };
        interfaces = ["enp2s0" "enp3s0" "enp4s0"];
      };
      vlans = [
        {
          name = "cameras";
          id = 30;
          subnet = "10.0.30";
          cidrPrefix = 24;
          dhcpRange = {
            start = 10;
            end = 50;
          };
          wanEgress = false;
          reservations = [];
        }
      ];
      wan.interface = "enp1s0";
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
          name = "chat.stark.pub";
          target = "10.0.0.1";
        }
        {
          name = "minne.stark.pub";
          target = "10.0.0.1";
        }
        {
          name = "request.stark.pub";
          target = "10.0.0.1";
        }
        {
          name = "vault.stark.pub";
          target = "10.0.0.1";
        }
        {
          name = "kube-test.lan.stark.pub";
          target = "10.0.0.1";
        }
        {
          name = "frigate.lan.stark.pub";
          target = "10.0.0.1";
        }
        {
          name = "nous.fyi";
          target = "10.0.0.1";
        }
        {
          name = "atuin.lan.stark.pub";
          target = "10.0.0.1";
        }
        {
          name = "webdav.lan.stark.pub";
          target = "10.0.0.1";
        }
        {
          name = "politikerstod.stark.pub";
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
            domain = "frigate.lan.stark.pub";
            target = "10.0.0.1";
            port = 5000;
            websockets = false;
            useWildcard = "lanstark";
          }
          {
            domain = "webdav.lan.stark.pub";
            target = "makemake";
            port = 8081;
            websockets = false;
            lanOnly = true;
            useWildcard = "lanstark";
            basicAuth = {
              realm = "WebDAV";
              htpasswdFile = config.my.secrets.getPath "webdav-htpasswd" "htpasswd";
            };
            extraConfig = ''
              # iOS WebDAV compatibility
              client_max_body_size 0;
              proxy_buffering off;
              proxy_request_buffering off;
              proxy_http_version 1.1;
              proxy_read_timeout 300s;
              proxy_send_timeout 300s;
            '';
          }
          {
            domain = "kube-test.lan.stark.pub";
            target = "10.0.0.10";
            port = 80;
            websockets = false;
            useWildcard = "lanstark";
          }
          {
            domain = "vault.stark.pub";
            target = "makemake";
            port = 8322;
            websockets = true;
            lanOnly = true;
            acmeDns01 = {
              dnsProvider = "cloudflare";
              environmentFile = config.my.secrets.getPath "api-key-cloudflare-dns" "api-token";
            };
          }
          {
            domain = "chat.stark.pub";
            target = "makemake";
            port = 8080;
            websockets = true;
            cloudflareOnly = true;
          }
          {
            domain = "request.stark.pub";
            target = "makemake";
            port = 5055;
            websockets = true;
            cloudflareOnly = true;
          }
          {
            domain = "minne.stark.pub";
            target = "makemake";
            port = 3000;
            websockets = false;
            cloudflareOnly = true;
            extraConfig = ''
              proxy_set_header Connection "close";
              proxy_http_version 1.1;
              chunked_transfer_encoding off;
              proxy_buffering off;
              proxy_cache off;
            '';
          }
          {
            domain = "minne-demo.stark.pub";
            target = "makemake";
            port = 3001;
            websockets = false;
            cloudflareOnly = true;
            extraConfig = ''
              proxy_set_header Connection "close";
              proxy_http_version 1.1;
              chunked_transfer_encoding off;
              proxy_buffering off;
              proxy_cache off;
            '';
          }
          {
            domain = "nous.fyi";
            target = "makemake";
            port = 3002;
            websockets = false;
            cloudflareOnly = true;
            extraConfig = ''
              client_max_body_size 55M;
            '';
          }
          {
            domain = "atuin.lan.stark.pub";
            target = "makemake";
            port = 8888;
            websockets = true;
            useWildcard = "lanstark";
          }
          {
            domain = "politikerstod.stark.pub";
            target = "makemake";
            port = 5150;
            websockets = false;
            cloudflareOnly = true;
          }
        ];
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
          ];
        };
        netdata.enable = false;
        ntopng.enable = false;
      };

      security = {
        enable = true;
        fail2ban = {
          enable = false;
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
  };

  # Custom nginx location for nous.fyi /app/ -> /assets/app/ rewrite
  # This merges with the router module's virtualHost config
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
