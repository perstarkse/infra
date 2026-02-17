{
  lib,
  pkgs,
  nixosModules,
  ...
}: let
  routerModules = with nixosModules; [
    router-core
    router-network
    router-firewall
    router-dhcp
    router-dns
    router-nginx
    router-monitoring
    router-wireguard
    router-security
  ];

  secretsStubModule = {lib, ...}: {
    options.my.secrets = {
      declarations = lib.mkOption {
        type = lib.types.listOf lib.types.anything;
        default = [];
      };
      mkMachineSecret = lib.mkOption {
        type = lib.types.anything;
        default = _: {};
      };
      getPath = lib.mkOption {
        type = lib.types.anything;
        default = _name: _file: "/run/empty-secret";
      };
    };
  };

  stateVersion = "25.11";

  commonNode = {
    networking.useNetworkd = true;
    networking.useDHCP = false;
    networking.firewall.enable = false;
    systemd.network.enable = true;
    system.stateVersion = stateVersion;
    environment.systemPackages = with pkgs; [
      curl
      dnsutils
      iproute2
      iputils
    ];
  };

  wanNode =
    commonNode
    // {
      virtualisation.vlans = [1];

      systemd.network.networks."10-eth1" = {
        matchConfig.Name = "eth1";
        address = ["192.168.100.1/24"];
        networkConfig.ConfigureWithoutCarrier = true;
      };

      services.dnsmasq = {
        enable = true;
        settings = {
          interface = "eth1";
          bind-interfaces = true;
          dhcp-authoritative = true;
          dhcp-range = ["192.168.100.50,192.168.100.150,255.255.255.0,12h"];
          dhcp-option = [
            "option:router,192.168.100.1"
            "option:dns-server,192.168.100.1"
          ];
        };
      };
    };

  lanClientNode =
    commonNode
    // {
      virtualisation.vlans = [2];
      systemd.network.networks."10-eth1" = {
        matchConfig.Name = "eth1";
        networkConfig.DHCP = "yes";
      };
    };

  lanServerNode =
    commonNode
    // {
      virtualisation.vlans = [2];
      systemd.network.networks."10-eth1" = {
        matchConfig.Name = "eth1";
        address = ["10.0.0.10/24"];
        networkConfig.ConfigureWithoutCarrier = true;
      };
    };

  lanServerHttpNode = lib.recursiveUpdate lanServerNode {
    systemd.services.lan-http = {
      description = "Test HTTP service on LAN server";
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "2s";
      };
      script = ''
        mkdir -p /var/lib/lan-http
        printf 'ok\n' > /var/lib/lan-http/index.html
        exec ${pkgs.busybox}/bin/httpd -f -p 8080 -h /var/lib/lan-http
      '';
    };
  };

  lanServerRoutedHttpNode = lib.recursiveUpdate lanServerHttpNode {
    systemd.network.networks."10-eth1".routes = [
      {
        Gateway = "10.0.0.1";
      }
    ];
  };

  camClientNode =
    commonNode
    // {
      virtualisation.vlans = [2];

      systemd.network.netdevs."10-vlan30" = {
        netdevConfig = {
          Name = "vlan30";
          Kind = "vlan";
        };
        vlanConfig.Id = 30;
      };

      systemd.network.networks."10-eth1" = {
        matchConfig.Name = "eth1";
        networkConfig = {
          ConfigureWithoutCarrier = true;
          VLAN = ["vlan30"];
        };
      };

      systemd.network.networks."20-vlan30" = {
        matchConfig.Name = "vlan30";
        networkConfig.DHCP = "yes";
      };
    };

  mkRouterNode = {
    extraRouterConfig ? {},
    extraConfig ? {},
  }:
    commonNode
    // extraConfig
    // {
      virtualisation.vlans = [1 2];
      imports = routerModules ++ [secretsStubModule];

      my.router =
        {
          enable = true;
          hostname = "router";

          wan.interface = "eth1";
          lan = {
            subnet = "10.0.0";
            interfaces = ["eth2"];
            dhcpRange = {
              start = 100;
              end = 200;
            };
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

          dhcp = {
            enable = true;
            domainName = "lan.test";
            validLifetime = 300;
            renewTimer = 120;
            rebindTimer = 240;
          };

          dns = {
            enable = true;
            localZones = ["lan.test."];
          };

          monitoring.enable = false;
          security.enable = false;
          wireguard.enable = false;
          nginx.enable = false;

          machines = [];
          services = [];
        }
        // extraRouterConfig;
    };
in {
  router-smoke = pkgs.testers.runNixOSTest {
    name = "router-smoke";
    nodes = {
      wan = wanNode;
      router = mkRouterNode {};
      lanClient = lanClientNode;
      lanServer = lanServerNode;
    };
    testScript = ''
      start_all()

      wan.wait_for_unit("dnsmasq.service")
      router.wait_for_unit("systemd-networkd.service")
      router.wait_for_unit("kea-dhcp4-server.service")
      router.wait_for_unit("unbound.service")

      lanServer.wait_until_succeeds("ip -4 -o addr show dev eth1 | grep -q '10.0.0.10/24'", timeout=120)
      lanClient.wait_until_succeeds("ip -4 -o addr show dev eth1 | grep -q '10\\.0\\.0\\.'", timeout=180)

      router.succeed("ping -c1 -W2 10.0.0.10")
      lanClient.succeed("ping -c1 -W2 10.0.0.1")
      lanClient.succeed("ping -c1 -W2 10.0.0.10")
      lanClient.succeed("ping -c1 -W2 192.168.100.1")

      lanClient.succeed("dig +short @10.0.0.1 router.lan.test A | grep -x '10.0.0.1'")
    '';
  };

  router-vlan-regression = pkgs.testers.runNixOSTest {
    name = "router-vlan-regression";
    nodes = {
      wan = wanNode;
      router = mkRouterNode {};
      lanClient = lanClientNode;
      lanServer = lanServerNode;
      camClient = camClientNode;
    };
    testScript = ''
      start_all()

      wan.wait_for_unit("dnsmasq.service")
      router.wait_for_unit("systemd-networkd.service")
      router.wait_for_unit("kea-dhcp4-server.service")

      lanClient.wait_until_succeeds("ip -4 -o addr show dev eth1 | grep -q '10\\.0\\.0\\.'", timeout=180)
      camClient.wait_until_succeeds("ip -4 -o addr show dev vlan30 | grep -q '10\\.0\\.30\\.'", timeout=180)

      router.succeed("ping -c1 -W2 10.0.0.10")
      lanClient.succeed("ping -c1 -W2 10.0.0.10")
      lanClient.succeed("ping -c1 -W2 192.168.100.1")

      camClient.succeed("ping -c1 -W2 10.0.30.1")
      camClient.fail("ping -c1 -W2 10.0.0.10")
      camClient.fail("ping -c1 -W2 192.168.100.1")
    '';
  };

  router-services = pkgs.testers.runNixOSTest {
    name = "router-services";
    nodes = {
      wan = wanNode;
      lanClient = lanClientNode;
      lanServer = lanServerHttpNode;
      router = mkRouterNode {
        extraRouterConfig = {
          security.enable = true;
          security.journalReceiver.enable = false;
          nginx = {
            enable = true;
            virtualHosts = [
              {
                domain = "status.lan.test";
                target = "lan-server";
                port = 8080;
                websockets = false;
                lanOnly = true;
                noAcme = true;
              }
            ];
          };
          machines = [
            {
              name = "lan-server";
              ip = "10";
              mac = "02:00:00:00:10:00";
              portForwards = [];
            }
          ];
          services = [
            {
              name = "status.lan.test";
              target = "10.0.0.10";
            }
          ];
        };
      };
    };
    testScript = ''
      start_all()

      wan.wait_for_unit("dnsmasq.service")
      lanServer.wait_for_unit("lan-http.service")
      lanClient.wait_until_succeeds("ip -4 -o addr show dev eth1 | grep -q '10\\.0\\.0\\.'", timeout=180)

      router.wait_for_unit("nginx.service")
      router.wait_for_unit("fail2ban.service")
      router.wait_for_unit("unbound.service")

      lanClient.succeed("dig +short @10.0.0.1 status.lan.test A | grep -x '10.0.0.10'")
      lanClient.succeed("curl --fail -sS -H 'Host: status.lan.test' http://10.0.0.1/ | grep -q '^ok$'")

      router_wan_ip = router.succeed("ip -4 -o addr show dev eth1 | awk '{print $4}' | cut -d/ -f1").strip()
      wan.fail(f"curl --fail -sS -H 'Host: status.lan.test' http://{router_wan_ip}/")
    '';
  };

  router-port-forward = pkgs.testers.runNixOSTest {
    name = "router-port-forward";
    nodes = {
      wan = wanNode;
      lanServer = lanServerRoutedHttpNode;
      router = mkRouterNode {
        extraRouterConfig = {
          machines = [
            {
              name = "lan-server";
              ip = "10";
              mac = "02:00:00:00:10:00";
              portForwards = [
                {
                  port = 8080;
                  protocol = "tcp";
                }
              ];
            }
          ];
        };
      };
    };
    testScript = ''
      start_all()

      wan.wait_for_unit("dnsmasq.service")
      lanServer.wait_for_unit("lan-http.service")
      router.wait_for_unit("systemd-networkd.service")
      router.wait_for_unit("kea-dhcp4-server.service")

      router.wait_until_succeeds("ip -4 -o addr show dev eth1 | grep -q '192\\.168\\.100\\.'", timeout=120)
      router.succeed("ping -c1 -W2 10.0.0.10")

      router_wan_ip = router.succeed("ip -4 -o addr show dev eth1 | awk '{print $4}' | cut -d/ -f1").strip()
      wan.succeed(f"curl --fail -sS --max-time 5 http://{router_wan_ip}:8080/ | grep -q '^ok$'")
      wan.fail(f"curl --fail -sS --max-time 5 http://{router_wan_ip}:18081/")
    '';
  };
}
