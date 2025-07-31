{
  modules,
  config,
  pkgs,
  ...
}: {
  imports = with modules.nixosModules;
    [
    ../../secrets.nix
      ./hardware-configuration.nix
      ./boot.nix
      interception-tools
      system-stylix
      shared
      router
      dns
      dhcp
      monitoring
      home-assistant
      nginx

    ];

  my.mainUser = {
    name = "p";
  };

  my.router = {
    enable = true;
    hostname = "io";
    lanSubnet = "10.0.0";
    dhcpStart = 100;
    dhcpEnd = 200;
    ulaPrefix = "fd00:711a:edcd:7e75";
    wanInterface = "enp1s0";
    lanInterfaces = ["enp2s0" "enp3s0" "enp4s0"];

    machines = [
      {
        name = "charon";
        ip = "15";
        mac = "f0:2f:74:de:91:0a";
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
      {
        name = "encke";
        ip = "156";
        mac = "52:54:00:a7:db:fe";
        portForwards = [];
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
        name = "encke.stark.pub";
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
    ];
  };

  my.dns = {
    enable = true;
    upstreamServers = [
      "1.1.1.1@853#cloudflare-dns.com"
      "1.0.0.1@853#cloudflare-dns.com"
      "2606:4700:4700::1111@853#cloudflare-dns.com"
      "2606:4700:4700::1001@853#cloudflare-dns.com"
    ];
    localZone = "lan.";
  };

  my.dhcp = {
    enable = true;
    validLifetime = 86400;
    renewTimer = 43200;
    rebindTimer = 75600;
    domainName = "lan";
  };

  my.monitoring = {
    enable = true;

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
        # Add more scrape configs as needed
      ];
    };

    netdata = {
      enable = false; # Disabled by default
    };
    ntopng = {
      enable = false; # Disabled by default
    };
  };

  my.nginx = {
    enable = true;
    acmeEmail = "services@stark.pub";
    
    virtualHosts = [
      {
        domain = "vault.stark.pub";
        target = "makemake";
        port = 8322;
        websockets = true;
      }
      {
        domain = "chat.stark.pub";
        target = "makemake";
        port = 7909;
        websockets = true;
      }
      {
        domain = "request.stark.pub";
        target = "makemake";
        port = 5055;
        websockets = true;
      }
      {
        domain = "encke.stark.pub";
        target = "encke";
        port = 3000;
        websockets = false;
        extraConfig = ''
          proxy_set_header Connection "close";
          proxy_http_version 1.1;
          chunked_transfer_encoding off;
          proxy_buffering off;
          proxy_cache off;
        '';
      }
      {
        domain = "minne.stark.pub";
        target = "makemake";
        port = 3000;
        websockets = false;
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
        extraConfig = ''
          proxy_set_header Connection "close";
          proxy_http_version 1.1;
          chunked_transfer_encoding off;
          proxy_buffering off;
          proxy_cache off;
        '';
      }
    ];
  };
} 