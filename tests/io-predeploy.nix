{
  lib,
  pkgs,
  nixosModules,
  ...
}: let
  pkgsUnfree = import pkgs.path {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };

  unwrapSingletonImports = m:
    if builtins.isAttrs m && m ? imports && builtins.length m.imports == 1
    then unwrapSingletonImports (builtins.elemAt m.imports 0)
    else m;

  routerModule = let
    unwrappedRouter = unwrapSingletonImports nixosModules.router;
  in
    if builtins.isFunction unwrappedRouter
    then
      unwrappedRouter {
        ctx.flake.nixosModules = nixosModules;
      }
    else nixosModules.router;

  testNixosModules =
    nixosModules
    // {
      router = routerModule;
      system-stylix = {};
    };

  secretsStubModule = {lib, ...}: {
    options.my.secrets = {
      declarations = lib.mkOption {
        type = lib.types.listOf lib.types.anything;
        default = [];
      };
      allowReadAccess = lib.mkOption {
        type = lib.types.listOf lib.types.anything;
        default = [];
      };
      generateManifest = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      discover = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
        dir = lib.mkOption {
          type = lib.types.path;
          default = /tmp;
        };
        includeTags = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
        };
      };
      mkMachineSecret = lib.mkOption {
        type = lib.types.anything;
        default = spec: spec;
      };
      getPath = lib.mkOption {
        type = lib.types.anything;
        default = name: file: "/etc/test-secrets/${name}/${file}";
      };
    };
  };

  varsHelperStub = {
    nixosModules.default = secretsStubModule;
  };

  nixTopologyStubModule = {lib, ...}: {
    options.topology.extractors.kea.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
  };

  clanDeploymentStubModule = {lib, ...}: {
    options.clan.core.deployment.requireExplicitUpdate = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
  };

  wireguardTestKeys = {
    routerPrivate = "eAcrKw/di4rNdd4YdfEMbawFXB7j2AKR2nM8WnxRu2o=";
    routerPublic = "Tx4IUngFH9q+qGdSr/BxIWnUlSbmWoxxRY+Juf/jnHs=";
  };

  commonNode = {
    networking = {
      useNetworkd = true;
      useDHCP = false;
      firewall.enable = false;
    };
    systemd.network.enable = true;
    system.stateVersion = "25.11";
    environment.systemPackages = with pkgsUnfree; [
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

  lanServerNode = lib.recursiveUpdate commonNode {
    virtualisation.vlans = [2];

    systemd = {
      network.networks."10-eth1" = {
        matchConfig.Name = "eth1";
        address = ["10.0.0.10/24"];
        routes = [
          {
            Gateway = "10.0.0.1";
          }
        ];
        networkConfig.ConfigureWithoutCarrier = true;
      };

      services.lan-http-32400 = {
        description = "LAN test HTTP service on 32400";
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "2s";
        };
        script = ''
          mkdir -p /var/lib/lan-http-32400
          printf 'predeploy\n' > /var/lib/lan-http-32400/index.html
          exec ${pkgsUnfree.busybox}/bin/httpd -f -p 32400 -h /var/lib/lan-http-32400
        '';
      };

      services.lan-http-18081 = {
        description = "LAN test HTTP service on 18081";
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "2s";
        };
        script = ''
          mkdir -p /var/lib/lan-http-18081
          printf 'blocked\n' > /var/lib/lan-http-18081/index.html
          exec ${pkgsUnfree.busybox}/bin/httpd -f -p 18081 -h /var/lib/lan-http-18081
        '';
      };
    };
  };

  ioNode = {lib, ...}: {
    imports = [
      clanDeploymentStubModule
      (args: let
        ioConfigRaw =
          import ../machines/io/configuration.nix
          (args
            // {
              pkgs = pkgsUnfree;
              ctx = {
                flake.nixosModules = testNixosModules;
                inputs = {
                  varsHelper = varsHelperStub;
                  nixTopology.nixosModules.default = nixTopologyStubModule;
                };
              };
            });
        ioImports = builtins.filter (
          m: let
            t = builtins.typeOf m;
            pathLike = t == "path" || t == "string";
            n =
              if pathLike
              then builtins.baseNameOf (toString m)
              else "";
          in
            !pathLike || (n != "hardware-configuration.nix" && n != "boot.nix")
        ) (ioConfigRaw.imports or []);
      in
        (builtins.removeAttrs ioConfigRaw ["nixpkgs"])
        // {
          imports = ioImports;
        })
    ];

    fileSystems = lib.mkForce {};
    swapDevices = lib.mkForce [];
    boot.loader.systemd-boot.enable = lib.mkForce false;
    boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

    virtualisation = {
      vlans = [1 2];
      memorySize = 4096;
      cores = 2;
      oci-containers.containers = lib.mkForce {};
    };

    my = {
      router = {
        wan.interface = lib.mkForce "eth1";
        lan.interfaces = lib.mkForce ["eth2"];
        wireguard.privateKeyFile = lib.mkForce "/etc/test-secrets/wireguard-server/private-key";
        wireguard.peers = lib.mkForce [];
      };

      # test-only: avoid generating install-time machine credentials.
      secrets.declarations = lib.mkForce [];

      # Keep test boot deterministic by avoiding VM-in-VM dependencies.
      libvirtd.enable = lib.mkForce false;
    };

    environment.etc = {
      "test-secrets/wireguard-server/private-key" = {
        text = wireguardTestKeys.routerPrivate;
        mode = "0440";
        user = "root";
        group = "systemd-network";
      };

      "test-secrets/wireguard-server/public-key" = {
        text = wireguardTestKeys.routerPublic;
        mode = "0444";
      };

      # Force all secret paths to exist for enabled services.
      "test-secrets/ddclient/ddclient.conf" = {
        text = "dummy";
        mode = "0400";
      };

      "test-secrets/api-key-cloudflare-dns/api-token" = {
        text = "CLOUDFLARE_API_TOKEN=dummy";
        mode = "0400";
      };

      "test-secrets/webdav-htpasswd/htpasswd" = {
        text = "webdav:$2y$10$hwzQHAl9zWgWii0Vf0D5.OXgEeGT0HnQf3pcSmceD1zDx0hDWQjQ2";
        mode = "0400";
      };

      "test-secrets/wake-proxy/env" = {
        text = ''
          WOL_PROXY_ADMIN_USERNAME=admin
          WOL_PROXY_ADMIN_PASSWORD=password
          WOL_PROXY_SESSION_SECRET=0123456789abcdef0123456789abcdef
        '';
        mode = "0400";
      };

      "test-secrets/garage/rpc_secret" = {
        text = "test-garage-rpc-secret";
        mode = "0400";
      };
    };

    services.unifi.enable = lib.mkForce false;

    # podman pulls are flaky in isolated test networks and not relevant for router predeploy.
    systemd.services = {
      podman-homeassistant.enable = lib.mkForce false;
      podman-frigate.enable = lib.mkForce false;
    };
  };
in {
  io-predeploy = pkgsUnfree.testers.runNixOSTest {
    name = "io-predeploy";
    nodes = {
      wan = wanNode;
      io = ioNode;
      lanClient = lanClientNode;
      lanServer = lanServerNode;
      camClient = camClientNode;
    };
    testScript = ''
      start_all()

      wan.wait_for_unit("dnsmasq.service")
      lanServer.wait_for_unit("lan-http-32400.service")
      lanServer.wait_for_unit("lan-http-18081.service")

      io.wait_for_unit("systemd-networkd.service")
      io.wait_for_unit("nftables.service")
      io.wait_for_unit("kea-dhcp4-server.service")
      io.wait_for_unit("unbound.service")

      io.wait_until_succeeds("ip -4 -o addr show dev eth1 | grep -q '192\\.168\\.100\\.'", timeout=240)
      io.wait_until_succeeds("ip -4 -o addr show dev vlan1 | grep -q '10\\.0\\.0\\.1/24'", timeout=240)
      io.wait_until_succeeds("ip -4 -o addr show dev wg0 | grep -q '10\\.6\\.0\\.1/24'", timeout=240)

      lanClient.wait_until_succeeds("ip -4 -o addr show dev eth1 | grep -q '10\\.0\\.0\\.'", timeout=240)
      camClient.wait_until_succeeds("ip -4 -o addr show dev vlan30 | grep -q '10\\.0\\.30\\.'", timeout=240)

      lanClient.succeed("ping -c1 -W2 10.0.0.1")
      lanClient.succeed("ping -c1 -W2 10.0.0.10")
      lanClient.succeed("ping -c1 -W2 192.168.100.1")

      camClient.succeed("ping -c1 -W2 10.0.30.1")
      camClient.fail("ping -c1 -W2 10.0.0.10")
      camClient.fail("ping -c1 -W2 192.168.100.1")

      lanClient.succeed("dig +short @10.0.0.1 io.lan.stark.pub A | grep -x '10.0.0.1'")
      lanClient.succeed("dig +short @10.0.0.1 mail.stark.pub A | grep -x '10.0.0.10'")

      io_wan_ip = io.succeed("ip -4 -o addr show dev eth1 | awk '{print $4}' | cut -d/ -f1").strip()

      wan.succeed(f"curl --fail -sS --max-time 5 http://{io_wan_ip}:32400/ | grep -q '^predeploy$'")

      blocked_code = wan.succeed(
        f"curl -sS -o /dev/null -w '%{{http_code}}' --max-time 5 http://{io_wan_ip}:18081/ || true"
      ).strip()
      assert blocked_code == "000", f"expected WAN non-forwarded port to be blocked, got HTTP {blocked_code}"
    '';
  };
}
