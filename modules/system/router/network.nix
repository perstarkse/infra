{
  config.flake.nixosModules.router-network = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.router;
    helpers = config.routerHelpers or (throw "routerHelpers not defined — is the router module loaded?");
    wan = helpers.wanInterface or cfg.wan.interface;
    bridgePorts = helpers.bridgePorts or [];
    lanBridge = helpers.lanBridge or "br-lan";
    segments = helpers.segments or [];
    routedInterfaces = map (segment: segment.interface) segments;
    bridgeSelfVlanMembership = map (segment: {VLAN = segment.vlanId;}) segments;
  in {
    config = lib.mkIf cfg.enable {
      boot.kernel.sysctl =
        {
          "net.ipv4.conf.all.forwarding" = true;
          "net.ipv4.conf.default.rp_filter" = 2;
          "net.ipv4.conf.${wan}.rp_filter" = 2;
          "net.ipv4.conf.${lanBridge}.rp_filter" = 2;
        }
        // lib.listToAttrs (map (
            segment: lib.nameValuePair "net.ipv4.conf.${segment.interface}.rp_filter" 2
          )
          segments)
        // {
          # Hard-hang mitigations (io Jul 2026): reboot after panic; panic on
          # detectable lockups so RuntimeWatchdog / panic= can recover the box.
          "kernel.panic" = 10;
          "kernel.softlockup_panic" = 1;
          "kernel.hardlockup_panic" = 1;
          "kernel.hung_task_panic" = 1;
        };

      # igc.eee_enable was never a real module param (ignored at boot).
      # pcie_aspm=off: BIOS still reports "can't disable ASPM; OS doesn't have
      # ASPM control" without this; keep pcie_port_pm=off as well.
      # Manual follow-up: disable ASPM in firmware if the option exists.
      boot.kernelParams = [
        "pcie_port_pm=off"
        "pcie_aspm=off"
      ];

      networking = {
        hostName = cfg.hostname;
        useNetworkd = true;
        useDHCP = false;
        networkmanager.enable = lib.mkForce false;
        firewall.enable = false;
      };

      # Pet the hardware watchdog so a full hang reboots within ~60s
      # (RuntimeWatchdogSec + default margin). Devices present on io:
      # intel_oc_wdt (/dev/watchdog0), iTCO_wdt (/dev/watchdog1).
      systemd.settings.Manager = {
        RuntimeWatchdogSec = "30s";
        RebootWatchdogSec = "10min";
      };

      systemd.network = {
        enable = true;
        wait-online = {
          enable = lib.mkForce true;
          extraArgs = map (iface: "--interface=${iface}") routedInterfaces;
          timeout = 30;
        };

        # Replace the dead igc.eee_enable=0 module param with systemd.link EEE off
        # (systemd >= 258 [EnergyEfficientEthernet] section).
        links."10-igc-no-eee" = {
          matchConfig.Driver = "igc";
          extraConfig = ''
            [EnergyEfficientEthernet]
            Enable=false
          '';
        };

        netdevs =
          {
            "20-${lanBridge}" = {
              netdevConfig = {
                Kind = "bridge";
                Name = lanBridge;
              };
              bridgeConfig.VLANFiltering = true;
            };
          }
          // lib.listToAttrs (map (
              segment:
                lib.nameValuePair "30-${segment.interface}" {
                  netdevConfig = {
                    Name = segment.interface;
                    Kind = "vlan";
                  };
                  vlanConfig.Id = segment.vlanId;
                }
            )
            segments);

        networks =
          {
            "20-wan" = {
              matchConfig.Name = wan;
              networkConfig = {
                DHCP = "yes";
                IPv4Forwarding = true;
              };
              linkConfig.RequiredForOnline = "routable";
            };

            "10-${lanBridge}" = {
              matchConfig.Name = lanBridge;
              bridgeVLANs = bridgeSelfVlanMembership;
              networkConfig = {
                ConfigureWithoutCarrier = true;
                VLAN = routedInterfaces;
              };
              linkConfig.RequiredForOnline = "no";
            };
          }
          // lib.listToAttrs (map (
              port:
                lib.nameValuePair "30-${port.name}-lan" {
                  matchConfig.Name = port.name;
                  bridgeVLANs = port.memberships;
                  networkConfig = {
                    Bridge = lanBridge;
                    ConfigureWithoutCarrier = true;
                  };
                }
            )
            bridgePorts)
          // lib.listToAttrs (map (
              segment:
                lib.nameValuePair "40-${segment.interface}" ({
                    matchConfig.Name = segment.interface;
                    address = ["${segment.routerIp}/${toString segment.cidrPrefix}"];
                    networkConfig.ConfigureWithoutCarrier = true;
                    linkConfig.RequiredForOnline = "no";
                  }
                  // lib.optionalAttrs (segment.linkMtu != null) {
                    linkConfig.MTUBytes = toString segment.linkMtu;
                  })
            )
            segments);
      };

      systemd.services.nftables = {
        after = ["sysinit.target"];
        before = ["network-pre.target"];
        wants = ["network-pre.target"];
      };
    };
  };
}
