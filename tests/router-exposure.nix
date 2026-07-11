{
  lib,
  pkgs,
  nixosModules,
  ...
}: let
  testHelpers = import ./lib/test-helpers.nix {inherit lib;};
  routerModule = nixosModules.router;

  secretsStubModule = import ./lib/secrets-stub.nix {
    inherit lib;
    getPathDefault = _name: _file: "/run/empty-secret";
  };

  commonNode = testHelpers.mkCommonNode {
    extraPackages = [pkgs.bind pkgs.python3];
  };

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
      router.succeed("dig +short @127.0.0.1 -p 5354 test.lan.test A | grep -x '10.0.0.1'")
    '';
  };

  router-exposure-lan-only-enforcement = pkgs.testers.runNixOSTest {
    name = "router-exposure-lan-only-enforcement";
    nodes.router = mkRouterNode {
      extraRouterConfig.dns.profiles.default.denyDomains = [];
      extraConfig.my.exposure.services.two-face = {
        upstream = {
          host = "127.0.0.1";
          port = 8080;
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

      # Start upstream test server on port 8080
      router.succeed(
          "mkdir -p /tmp/upstream && echo '<html><head><title>NixOS</title></head><body>OK</body></html>' > /tmp/upstream/index.html"
      )
      router.succeed("systemd-run --unit=test-upstream --working-directory=/tmp/upstream python3 -m http.server 8080")
      router.wait_for_open_port(8080)

      # Open service: public=true means no ACL, accessible from anywhere
      router.succeed(
          "curl --fail -sS --max-time 5 -H 'Host: open.lan.test' http://127.0.0.1/ | grep -q '<title>NixOS'"
      )

      # Locked (lanOnly) blocked from non-LAN IPs with 403
      locked_status = router.succeed(
          "curl -sS -o /dev/null -w '%{http_code}' --max-time 5 -H 'Host: locked.lan.test' http://127.0.0.1/ || true"
      ).strip()
      assert locked_status == "403", f"expected non-LAN lan-only to be denied, got HTTP {locked_status}"
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
      router.succeed("dig +short @127.0.0.1 -p 5354 auto.lan.test A | grep -x '127.0.0.1'")
    '';
  };

  router-exposure-extra-config = pkgs.testers.runNixOSTest {
    name = "router-exposure-extra-config";
    nodes.router = mkRouterNode {
      extraRouterConfig.dns.profiles.default.denyDomains = [];
      extraConfig.my.exposure.services.extra-cfg = {
        upstream = {
          host = "127.0.0.1";
          port = 8080;
        };
        http.virtualHosts = [
          {
            domain = "extra.lan.test";
            public = true;
            noAcme = true;
            extraConfig = "add_header X-Exposure-Test extra-config;";
          }
        ];
      };
    };
    testScript = ''
      start_all()
      router.wait_for_unit("nginx.service")

      # Start upstream test server on port 8080
      router.succeed("mkdir -p /tmp/upstream")
      router.succeed("systemd-run --unit=test-upstream --working-directory=/tmp/upstream python3 -m http.server 8080")
      router.wait_for_open_port(8080)

      result = router.succeed(
          "curl -sS -I --max-time 5 -H 'Host: extra.lan.test' http://127.0.0.1/"
      )
      assert "x-exposure-test: extra-config" in result.lower(), f"expected X-Exposure-Test header, got: {result}"
    '';
  };

  # Regression for the ACME DNS-01 bug: an exposure vhost declaring acmeDns01
  # must emit a DNS-01 security.acme.certs entry. Previously the cert loop in
  # router/nginx.nix only iterated router-side vhosts, so acmeDns01 on an
  # exposure vhost was silently dropped and the vhost fell back to the
  # enableACME=true HTTP-01 default.
  router-exposure-acme-dns01 = pkgs.testers.runNixOSTest {
    name = "router-exposure-acme-dns01";
    nodes.router = mkRouterNode {
      extraRouterConfig.dns.profiles.default.denyDomains = [];
      extraConfig.my.exposure.services.dns01-svc = {
        upstream = {
          host = "127.0.0.1";
          port = 8080;
        };
        http.virtualHosts = [
          {
            domain = "dns01.lan.test";
            lanOnly = true;
            acmeDns01 = {
              dnsProvider = "cloudflare";
              environmentFile = "/run/secrets/acme-cloudflare-env";
            };
          }
        ];
      };
    };
    testScript = ''
      start_all()
      router.wait_for_unit("multi-user.target")

      cert_unit = "acme-order-renew-dns01.lan.test.service"
      unit = router.succeed(f"systemctl cat {cert_unit}")

      # environmentFile is only emitted when our acmeDns01 loop ran — the
      # HTTP-01 fallback from enableACME=true never sets it.
      assert "EnvironmentFile=/run/secrets/acme-cloudflare-env" in unit, (
          "acmeDns01.environmentFile missing from cert unit — "
          "exposure vhost fell back to HTTP-01 (regression)"
      )

      # Confirm DNS-01 (lego --dns) rather than HTTP-01 (--http.webroot).
      # `systemctl show -p ExecStart --value` returns systemd's structured
      # form `{ path=...; argv=[...]; ... }`; pull the `path=` field out of it.
      exec_start = router.succeed(f"systemctl show -p ExecStart --value {cert_unit}").strip()
      start = exec_start.find("path=")
      assert start != -1, f"could not find ExecStart path in: {exec_start!r}"
      script_path = exec_start[start + len("path=") : exec_start.find(";", start)].strip()
      assert script_path, f"empty ExecStart path in: {exec_start!r}"
      script_text = router.succeed(f"cat {script_path}")
      assert "--dns cloudflare" in script_text, (
          "lego not invoked with --dns cloudflare; cert is not DNS-01"
      )
    '';
  };
}
