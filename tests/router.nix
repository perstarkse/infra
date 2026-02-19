{
  lib,
  pkgs,
  nixosModules,
  ...
}: let
  routerModule = let
    unwrapSingletonImports = m:
      if builtins.isAttrs m && m ? imports && builtins.length m.imports == 1
      then unwrapSingletonImports (builtins.elemAt m.imports 0)
      else m;
    unwrappedRouter = unwrapSingletonImports nixosModules.router;
  in
    if builtins.isFunction unwrappedRouter
    then
      unwrappedRouter {
        ctx.flake.nixosModules = nixosModules;
      }
    else nixosModules.router;

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

  wireguardTestKeys = {
    routerPrivate = "eAcrKw/di4rNdd4YdfEMbawFXB7j2AKR2nM8WnxRu2o=";
    routerPublic = "Tx4IUngFH9q+qGdSr/BxIWnUlSbmWoxxRY+Juf/jnHs=";
    clientPrivate = "KFjwd3aVdMJqJRT7ByNj5w+00iftHHE0xRqYgRQVCEc=";
    clientPublic = "SGkU1Asb0JDGFwRrymM/i22qRu+4J6AwEHJMMClELDU=";
  };

  commonNode = {
    networking = {
      useNetworkd = true;
      useDHCP = false;
      firewall.enable = false;
    };
    systemd.network.enable = true;
    system.stateVersion = stateVersion;
    environment.systemPackages = with pkgs; [
      curl
      dnsutils
      iproute2
      iputils
    ];
  };

  wanNode = lib.recursiveUpdate commonNode {
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

  lanClientNode = lib.recursiveUpdate commonNode {
    virtualisation.vlans = [2];
    systemd.network.networks."10-eth1" = {
      matchConfig.Name = "eth1";
      networkConfig.DHCP = "yes";
    };
  };

  lanServerNode = lib.recursiveUpdate commonNode {
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

  lanServerDualHttpNode = lib.recursiveUpdate lanServerRoutedHttpNode {
    systemd.services.lan-http-alt = {
      description = "Auxiliary HTTP service on LAN server";
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "2s";
      };
      script = ''
        mkdir -p /var/lib/lan-http-alt
        printf 'alt\n' > /var/lib/lan-http-alt/index.html
        exec ${pkgs.busybox}/bin/httpd -f -p 18081 -h /var/lib/lan-http-alt
      '';
    };
  };

  camClientNode = lib.recursiveUpdate commonNode {
    virtualisation.vlans = [2];

    systemd = {
      network = {
        netdevs."10-vlan30" = {
          netdevConfig = {
            Name = "vlan30";
            Kind = "vlan";
          };
          vlanConfig.Id = 30;
        };

        networks."10-eth1" = {
          matchConfig.Name = "eth1";
          networkConfig = {
            ConfigureWithoutCarrier = true;
            VLAN = ["vlan30"];
          };
        };

        networks."20-vlan30" = {
          matchConfig.Name = "vlan30";
          networkConfig.DHCP = "yes";
        };
      };
    };
  };

  wgClientNode = lib.recursiveUpdate commonNode {
    virtualisation.vlans = [1];

    systemd.network.networks."10-eth1" = {
      matchConfig.Name = "eth1";
      networkConfig.DHCP = "yes";
    };

    environment.systemPackages = with pkgs; [
      curl
      dnsutils
      iproute2
      iputils
      wireguard-tools
    ];

    environment.etc."wg-client.key" = {
      text = wireguardTestKeys.clientPrivate;
      mode = "0400";
    };
  };

  mkRouterNode = {
    extraRouterConfig ? {},
    extraConfig ? {},
  }:
    lib.recursiveUpdate (lib.recursiveUpdate commonNode extraConfig) {
      virtualisation.vlans = [1 2];
      imports = [routerModule secretsStubModule];

      my.router =
        lib.recursiveUpdate
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
        extraRouterConfig;
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

      wan_status = wan.succeed(
        f"curl -sS -o /dev/null -w '%{{http_code}}' --max-time 5 -H 'Host: status.lan.test' http://{router_wan_ip}/"
      ).strip()
      assert wan_status == "403", f"expected WAN lan-only request to return 403, got {wan_status}"

      wan.succeed(
        f"for _ in $(seq 1 6); do curl -sS -o /dev/null --max-time 3 -H 'Host: status.lan.test' http://{router_wan_ip}/wp-admin || true; done"
      )
      router.wait_until_succeeds("fail2ban-client status nginx-url-probe | grep -q '192\\.168\\.100\\.1'", timeout=120)
      router.wait_until_succeeds("nft list ruleset | grep -q '192\\.168\\.100\\.1'", timeout=120)
    '';
  };

  router-port-forward = pkgs.testers.runNixOSTest {
    name = "router-port-forward";
    nodes = {
      wan = wanNode;
      lanServer = lanServerDualHttpNode;
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
      lanServer.wait_for_unit("lan-http-alt.service")
      router.wait_for_unit("systemd-networkd.service")
      router.wait_for_unit("kea-dhcp4-server.service")

      router.wait_until_succeeds("ip -4 -o addr show dev eth1 | grep -q '192\\.168\\.100\\.'", timeout=120)
      router.succeed("ping -c1 -W2 10.0.0.10")
      router.succeed("curl --fail -sS --max-time 5 http://10.0.0.10:8080/ | grep -q '^ok$'")
      router.succeed("curl --fail -sS --max-time 5 http://10.0.0.10:18081/ | grep -q '^alt$'")

      router_wan_ip = router.succeed("ip -4 -o addr show dev eth1 | awk '{print $4}' | cut -d/ -f1").strip()

      wan.succeed(f"ip route replace 10.0.0.0/24 via {router_wan_ip} dev eth1")

      direct_lan_code = wan.succeed("curl -sS -o /dev/null -w '%{http_code}' --max-time 5 http://10.0.0.10:18081/ || true").strip()
      assert direct_lan_code == "000", f"expected WAN direct-to-LAN access to fail closed, got HTTP {direct_lan_code}"

      wan_forward_code = wan.succeed(
        f"curl -sS -o /dev/null -w '%{{http_code}}' --max-time 5 http://{router_wan_ip}:8080/"
      ).strip()
      assert wan_forward_code == "200", f"expected forwarded WAN port to return HTTP 200, got {wan_forward_code}"
      wan.succeed(f"curl --fail -sS --max-time 5 http://{router_wan_ip}:8080/ | grep -q '^ok$'")

      wan_blocked_code = wan.succeed(
        f"curl -sS -o /dev/null -w '%{{http_code}}' --max-time 5 http://{router_wan_ip}:18081/ || true"
      ).strip()
      assert wan_blocked_code == "000", f"expected non-forwarded WAN port to be blocked, got HTTP {wan_blocked_code}"
    '';
  };

  router-wireguard = pkgs.testers.runNixOSTest {
    name = "router-wireguard";
    nodes = {
      wan = wanNode;
      wgClient = wgClientNode;
      router = mkRouterNode {
        extraConfig = {
          environment.etc."wireguard-server.key" = {
            text = wireguardTestKeys.routerPrivate;
            mode = "0440";
            user = "root";
            group = "systemd-network";
          };
        };
        extraRouterConfig = {
          wireguard = {
            enable = true;
            privateKeyFile = "/etc/wireguard-server.key";
            peers = [
              {
                name = "wg-client";
                ip = 2;
                publicKey = wireguardTestKeys.clientPublic;
                autoGenerate = false;
              }
            ];
          };
        };
      };
    };
    testScript = ''
      start_all()

      wan.wait_for_unit("dnsmasq.service")
      router.wait_for_unit("systemd-networkd.service")
      router.wait_until_succeeds("ip -4 -o addr show dev eth1 | grep -q '192\\.168\\.100\\.'", timeout=120)
      router.wait_until_succeeds("ip -4 -o addr show dev wg0 | grep -q '10\\.6\\.0\\.1/24'", timeout=120)
      wgClient.wait_until_succeeds("ip -4 -o addr show dev eth1 | grep -q '192\\.168\\.100\\.'", timeout=180)

      router_wan_ip = router.succeed("ip -4 -o addr show dev eth1 | awk '{print $4}' | cut -d/ -f1").strip()

      wgClient.succeed("ip link add wg0 type wireguard")
      wgClient.succeed("ip address add 10.6.0.2/24 dev wg0")
      wgClient.succeed(
        f"wg set wg0 private-key /etc/wg-client.key peer ${wireguardTestKeys.routerPublic} allowed-ips 10.6.0.0/24 endpoint {router_wan_ip}:51820 persistent-keepalive 1"
      )
      wgClient.succeed("ip link set up dev wg0")

      wgClient.succeed("ping -c1 -W5 10.6.0.1")
      router.succeed("ping -c1 -W5 10.6.0.2")
      wgClient.wait_until_succeeds("wg show wg0 latest-handshakes | awk '{print $2}' | grep -Eq '^[1-9][0-9]*$'", timeout=120)
    '';
  };
}
