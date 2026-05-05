{
  lib,
  pkgs,
  nixosModules,
  ...
}: let
  stateVersion = "25.11";

  testHelpers = import ./lib/test-helpers.nix {inherit lib;};
  routerModule = testHelpers.mkRouterModule nixosModules;

  secretsStubModule = import ./lib/secrets-stub.nix {
    inherit lib;
    getPathDefault = _name: _file: "/run/empty-secret";
  };

  commonNode = testHelpers.mkCommonNode {inherit stateVersion;};

  mkRouterNode = {
    extraRouterConfig ? {},
    extraConfig ? {},
  }:
    lib.recursiveUpdate (lib.recursiveUpdate commonNode extraConfig) {
      virtualisation.vlans = [1 2];
      imports = [routerModule secretsStubModule nixosModules.options];

      my.router =
        lib.recursiveUpdate
        {
          enable = true;
          hostname = "router";
          primarySegment = "trusted";

          wan.interface = "eth1";
          ports.eth2 = {
            mode = "trunk";
            nativeSegment = "trusted";
            taggedSegments = ["iot"];
          };
          segments = {
            trusted = {
              vlan.id = 1;
              subnet = "10.0.0";
              dhcp.range = {
                start = 100;
                end = 200;
              };
            };
            iot = {
              vlan.id = 20;
              subnet = "10.0.20";
              dhcp.range = {
                start = 10;
                end = 50;
              };
            };
          };

          dhcp = {
            enable = true;
            domainName = "lan.test";
          };
          dns = {
            enable = true;
            localZones = ["lan.test."];
          };
          nginx = {enable = true;};
          wireguard.enable = false;
          monitoring.enable = false;
          security.enable = false;
          machines = [];
          services = [];
        }
        extraRouterConfig;
    };
in {
  router-exposure-smoke = pkgs.testers.runNixOSTest {
    name = "router-exposure-smoke";
    nodes.router = mkRouterNode {extraRouterConfig.dns.profiles.default.denyDomains = [];};
    testScript = ''
      start_all()
      router.wait_for_unit("multi-user.target")
      router.wait_for_unit("systemd-networkd.service")
      router.wait_for_unit("kea-dhcp4-server.service")
      router.wait_for_unit("nginx.service")
      router.wait_for_unit("unbound.service")
      router.succeed("true")
    '';
  };

  router-exposure-dns-and-vhost = pkgs.testers.runNixOSTest {
    name = "router-exposure-dns-and-vhost";
    nodes.router = mkRouterNode {
      extraRouterConfig.dns.profiles.default.denyDomains = [];
      extraConfig.my.exposure.services.test-svc = {
        upstream = {
          host = "10.0.0.10";
          port = 8080;
        };
        http.virtualHosts = [
          {
            domain = "test.lan.test";
            lanOnly = true;
            noAcme = true;
          }
        ];
        dns.records = [
          {
            name = "test.lan.test";
            target = "10.0.0.1";
          }
        ];
      };
    };
    testScript = ''
      start_all()
      router.wait_for_unit("nginx.service")
      router.wait_for_unit("unbound.service")
      router.succeed("dig +short @127.0.0.1 test.lan.test A | grep -x '10.0.0.1'")
    '';
  };

  router-exposure-lan-only-enforcement = pkgs.testers.runNixOSTest {
    name = "router-exposure-lan-only-enforcement";
    nodes.router = mkRouterNode {
      extraRouterConfig.dns.profiles.default.denyDomains = [];
      extraConfig.my.exposure.services.two-face = {
        upstream = {
          host = "127.0.0.1";
          port = 80;
        };
        http.virtualHosts = [
          {
            domain = "locked.lan.test";
            lanOnly = true;
            noAcme = true;
          }
          {
            domain = "open.lan.test";
            public = true;
            noAcme = true;
          }
        ];
      };
    };
    testScript = ''
      start_all()
      router.wait_for_unit("nginx.service")

      router_wan_ip = router.succeed(
          "ip -4 -o addr show dev eth1 | awk '{print $4}' | cut -d/ -f1"
      ).strip()

      # Open service accessible from WAN side
      router.succeed(
          f"curl --fail -sS --max-time 5 -H 'Host: open.lan.test' http://{router_wan_ip}/ | grep -q '<title>NixOS'"
      )

      # Locked (lanOnly) blocked from WAN with 403
      locked_status = router.succeed(
          f"curl -sS -o /dev/null -w '%{{http_code}}' --max-time 5 -H 'Host: locked.lan.test' http://{router_wan_ip}/ || true"
      ).strip()
      assert locked_status == "403", f"expected WAN lan-only to be denied, got HTTP {locked_status}"
    '';
  };

  router-exposure-dns-auto = pkgs.testers.runNixOSTest {
    name = "router-exposure-dns-auto";
    nodes.router = mkRouterNode {
      extraRouterConfig.dns.profiles.default.denyDomains = [];
      extraConfig.my.exposure.services.auto-dns = {
        upstream = {
          host = "127.0.0.1";
          port = 80;
        };
        http.virtualHosts = [
          {
            domain = "auto.lan.test";
            lanOnly = true;
            noAcme = true;
          }
        ];
      };
    };
    testScript = ''
      start_all()
      router.wait_for_unit("unbound.service")
      router.succeed("dig +short @127.0.0.1 auto.lan.test A | grep -x '10.0.0.1'")
    '';
  };

  router-exposure-extra-config = pkgs.testers.runNixOSTest {
    name = "router-exposure-extra-config";
    nodes.router = mkRouterNode {
      extraRouterConfig.dns.profiles.default.denyDomains = [];
      extraConfig.my.exposure.services.extra-cfg = {
        upstream = {
          host = "127.0.0.1";
          port = 80;
        };
        http.virtualHosts = [
          {
            domain = "extra.lan.test";
            lanOnly = true;
            noAcme = true;
            extraConfig = "add_header X-Exposure-Test extra-config;";
          }
        ];
      };
    };
    testScript = ''
      start_all()
      router.wait_for_unit("nginx.service")

      result = router.succeed(
          "curl -sS -I --max-time 5 -H 'Host: extra.lan.test' http://127.0.0.1/"
      )
      assert "x-exposure-test: extra-config" in result.lower(), f"expected X-Exposure-Test header, got: {result}"
    '';
  };
}
