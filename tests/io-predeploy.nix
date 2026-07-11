{
  lib,
  pkgs,
  nixosModules,
  ...
}: let
  testHelpers = import ./lib/test-helpers.nix {inherit lib;};
  pkgsUnfree = testHelpers.mkUnfreePkgs pkgs;
  routerModule = nixosModules.router;

  testNixosModules =
    nixosModules
    // {
      router = routerModule;
      stylix = {lib, ...}: {
        options.my.stylix = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
        };
        config = {};
      };
      # Avoid nixpkgs overlay mutations in NixOS test eval (read-only pkgs).
      shared = {};
    };

  secretsStubModule = import ./lib/secrets-stub.nix {
    inherit lib;
    getPathDefault = name: file: "/etc/test-secrets/${name}/${file}";
    mkMachineSecretDefault = spec: spec;
    withDiscover = true;
    withAllowReadAccess = true;
    withGenerateManifest = true;
  };

  varsHelperStub = {
    nixosModules.default = secretsStubModule;
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
    clientPrivate = "KFjwd3aVdMJqJRT7ByNj5w+00iftHHE0xRqYgRQVCEc=";
    clientPublic = "SGkU1Asb0JDGFwRrymM/i22qRu+4J6AwEHJMMClELDU=";
  };

  commonNode = testHelpers.mkCommonNode {
    stateVersion = "25.11";
    extraPackages = with pkgsUnfree; [curl dnsutils iproute2 iputils wireguard-tools];
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

  wireguardClientNode = lib.recursiveUpdate commonNode {
    environment.etc."wg-client.key" = {
      text = wireguardTestKeys.clientPrivate;
      mode = "0400";
    };
  };

  wgClientNode = lib.recursiveUpdate wireguardClientNode {
    virtualisation.vlans = [1];
    systemd.network.networks."10-eth1" = {
      matchConfig.Name = "eth1";
      networkConfig.DHCP = "yes";
    };
  };

  lanClientNode = lib.recursiveUpdate wireguardClientNode {
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
                flake = {
                  nixosModules = testNixosModules;
                  lib = {
                    exposure = import ../flake/lib/exposure.nix {inherit (pkgs) lib;};
                  };
                };
                inputs = {
                  varsHelper = varsHelperStub;
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
        ports = lib.mkForce {
          eth2 = {
            mode = "trunk";
            nativeSegment = "trusted";
            taggedSegments = ["cameras"];
          };
        };
        wireguard.privateKeyFile = lib.mkForce "/etc/test-secrets/wireguard-server/private-key";
        wireguard.peers = lib.mkForce [
          {
            name = "vm-client";
            ip = 2;
            autoGenerate = true;
          }
        ];
      };

      # test-only: avoid generating install-time machine credentials.
      secrets.declarations = lib.mkForce [];

      # Keep test boot deterministic by avoiding VM-in-VM dependencies.
      libvirt.enable = lib.mkForce false;
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

      "test-secrets/wireguard-peer-vm-client/public-key" = {
        text = wireguardTestKeys.clientPublic;
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
          WAKEPROXY_PASSWORD_HASH=$argon2id$v=19$m=19456,t=2,p=1$dGVzdHRlc3R0ZXN0dGVzdA$0xDPfypM3Y76kJumWn95v9PoW7A1WeNseyX2VINeodQ
          WAKEPROXY_SESSION_SECRET=0123456789abcdef0123456789abcdef
        '';
        mode = "0400";
      };

      "test-secrets/garage/rpc_secret" = {
        text = "test-garage-rpc-secret";
        mode = "0400";
      };
    };
    environment.systemPackages = [pkgsUnfree.wireguard-tools];

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
      io.wait_for_unit("blocky.service")

      io.wait_until_succeeds("ip -4 -o addr show dev eth1 | grep -q '192\\.168\\.100\\.'", timeout=240)
      io.wait_until_succeeds("ip -4 -o addr show dev vlan1 | grep -q '10\\.0\\.0\\.1/24'", timeout=240)
      io.wait_until_succeeds("ip -4 -o addr show dev wg0 | grep -q '10\\.6\\.0\\.1/24'", timeout=240)

      lanClient.wait_until_succeeds("ip -4 -o addr show dev eth1 | grep -q '10\\.0\\.0\\.'", timeout=240)
      lanClient.wait_until_succeeds("dig +short @10.0.0.1 io.lan.stark.pub A | grep -x '10.0.0.1'", timeout=240)
      lanClient.wait_until_succeeds("dig +short @10.0.0.1 mail.stark.pub A | grep -x '10.0.0.10'", timeout=240)
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

  io-wireguard = pkgsUnfree.testers.runNixOSTest {
    name = "io-wireguard";
    nodes = {
      wan = wanNode;
      io = ioNode;
      wgClient = wgClientNode;
      lanClient = lanClientNode;
      lanServer = lanServerNode;
      camClient = camClientNode;
    };
    testScript = ''
      start_all()

      wan.wait_for_unit("dnsmasq.service")
      lanServer.wait_for_unit("lan-http-32400.service")
      io.wait_for_unit("systemd-networkd.service")
      io.wait_for_unit("nftables.service")
      io.wait_for_unit("blocky.service")

      io.wait_until_succeeds("ip -4 -o addr show dev eth1 | grep -q '192\\.168\\.100\\.'", timeout=240)
      io.wait_until_succeeds("ip -4 -o addr show dev vlan1 | grep -q '10\\.0\\.0\\.1/24'", timeout=240)
      io.wait_until_succeeds("ip -4 -o addr show dev wg0 | grep -q '10\\.6\\.0\\.1/24'", timeout=240)
      io.wait_until_succeeds("wg show wg0 peers | grep -q .", timeout=60)
      io.succeed("nft list table ip filterV4 | grep -Eq 'iifname \"vlan60\".*maxseg size set 1280'")

      wgClient.wait_until_succeeds("ip -4 -o addr show dev eth1 | grep -q '192\\.168\\.100\\.'", timeout=240)
      lanClient.wait_until_succeeds("ip -4 -o addr show dev eth1 | grep -q '10\\.0\\.0\\.'", timeout=240)
      camClient.wait_until_succeeds("ip -4 -o addr show dev vlan30 | grep -q '10\\.0\\.30\\.'", timeout=240)
      io_wan_ip = io.succeed("ip -4 -o addr show dev eth1 | awk '{print $4}' | cut -d/ -f1").strip()

      wgClient.succeed("ip link add wg0 type wireguard")
      wgClient.succeed("ip address add 10.6.0.2/24 dev wg0")
      wgClient.succeed(
        f"wg set wg0 private-key /etc/wg-client.key peer ${wireguardTestKeys.routerPublic} "
        f"allowed-ips 10.6.0.0/24,10.0.0.0/16 endpoint {io_wan_ip}:51820 persistent-keepalive 1"
      )
      wgClient.succeed("ip link set up dev wg0")
      wgClient.succeed("ip route add 10.0.0.0/16 dev wg0")
      wgClient.succeed("ping -c1 -W5 10.6.0.1")
      wgClient.wait_until_succeeds(
        "wg show wg0 latest-handshakes | awk '{print $2}' | grep -Eq '^[1-9][0-9]*$'",
        timeout=120,
      )
      wgClient.succeed("curl --fail -sS --max-time 5 http://10.0.0.10:32400/ | grep -q '^predeploy$'")
      wgClient.wait_until_succeeds(
        "dig +short @10.0.0.1 io.lan.stark.pub A | grep -x '10.0.0.1'",
        timeout=120,
      )
      cam_ip = camClient.succeed("ip -4 -o addr show dev vlan30 | awk '{print $4}' | cut -d/ -f1").strip()
      wgClient.fail(f"ping -c1 -W2 {cam_ip}")

      wgClient.succeed("ip link delete wg0")
      lanClient.succeed("ip link add wg0 type wireguard")
      lanClient.succeed("ip address add 10.6.0.2/24 dev wg0")
      lanClient.succeed(
        "wg set wg0 private-key /etc/wg-client.key peer ${wireguardTestKeys.routerPublic} "
        "allowed-ips 10.6.0.0/24 endpoint 10.0.0.1:51820 persistent-keepalive 1"
      )
      lanClient.succeed("ip link set up dev wg0")
      lanClient.succeed("ping -c1 -W5 10.6.0.1")

      io.succeed("networkctl reload")
      io.succeed("networkctl reconfigure wg0")
      io.wait_until_succeeds("wg show wg0 peers | grep -q .", timeout=60)
      lanClient.succeed("ping -c1 -W5 10.6.0.1")
    '';
  };
}
