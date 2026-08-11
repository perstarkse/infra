{
  config.flake.nixosModules.router-network = {
    lib,
    config,
    pkgs,
    ...
  }: let
    cfg = config.my.router;
    helpers = config.routerHelpers or (throw "routerHelpers not defined — is the router module loaded?");
    wan = helpers.wanInterface or cfg.wan.interface;
    bridgePorts = helpers.bridgePorts or [];
    lanBridge = helpers.lanBridge or "br-lan";
    segments = helpers.segments or [];
    routedInterfaces = map (segment: segment.interface) segments;
    primaryInterface = helpers.primaryInterface or (builtins.head routedInterfaces);
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
        # Router boot must not wait on WAN DHCP / ISP link. Only require the
        # primary LAN segment (ConfigureWithoutCarrier + static address).
        wait-online = {
          enable = lib.mkForce true;
          any = true;
          extraArgs = ["--interface=${primaryInterface}"];
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
              # Never gate network-online / boot on ISP DHCP. A dead WAN PHY
              # (common on Intel I226/igc) must not block LAN bring-up.
              linkConfig.RequiredForOnline = "no";
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
                    # Primary is selected explicitly via wait-online --interface=;
                    # keep RequiredForOnline=no so a cable-less lab boot still
                    # configures the static address (ConfigureWithoutCarrier).
                    linkConfig.RequiredForOnline = "no";
                  }
                  // lib.optionalAttrs (segment.linkMtu != null) {
                    linkConfig.MTUBytes = toString segment.linkMtu;
                  })
            )
            segments);
      };

      # Belt-and-suspenders for Intel I225/I226 (igc): systemd.link EEE=off is
      # not always applied before the first link train. Disable via ethtool
      # before networkd configures the iface; only bounce WAN when link is
      # already down so a healthy link is not disrupted on every boot.
      systemd.services."igc-disable-eee" = {
        description = "Disable Energy Efficient Ethernet on igc NICs";
        wantedBy = ["network-pre.target"];
        before = ["network-pre.target"];
        after = ["systemd-udev-settle.service"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "igc-disable-eee" ''
            set -eu
            ethtool=${pkgs.ethtool}/bin/ethtool
            ip=${pkgs.iproute2}/bin/ip
            for nic in /sys/class/net/*; do
              iface=$(basename "$nic")
              case "$iface" in
                lo|bonding_masters) continue ;;
              esac
              driver=$(basename "$(readlink -f "$nic/device/driver" 2>/dev/null || true)" 2>/dev/null || true)
              if [ "$driver" != "igc" ]; then
                continue
              fi
              $ethtool --set-eee "$iface" eee off 2>/dev/null || true
            done
            # I226 often trains once with EEE on and leaves the link dark.
            # Bounce WAN only when carrier is absent so healthy boots are quiet.
            if [ -d /sys/class/net/${wan} ]; then
              $ethtool --set-eee ${wan} eee off 2>/dev/null || true
              carrier=$(cat /sys/class/net/${wan}/carrier 2>/dev/null || echo 0)
              if [ "$carrier" != "1" ]; then
                $ip link set ${wan} down || true
                $ip link set ${wan} up || true
              fi
            fi
          '';
        };
      };

      systemd.services.nftables = {
        after = ["sysinit.target"];
        before = ["network-pre.target"];
        wants = ["network-pre.target"];
      };
    };
  };
}
