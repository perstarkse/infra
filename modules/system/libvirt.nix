{inputs, ...}: {
  config.flake.nixosModules.libvirt = {
    lib,
    config,
    pkgs,
    ...
  }: let
    cfg = config.my.libvirtd;
  in {
    imports = [
      inputs.NixVirt.nixosModules.default
    ];
    options.my.libvirtd = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable NixVirt for declarative libvirt management.";
      };

      spiceUSBRedirection = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable SPICE USB redirection support.";
      };

      shutdownOnSuspend = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Shutdown selected VMs when host suspends.";
        };

        vms = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "List of VM names to shutdown before host suspend.";
        };
      };

      # Network configuration options
      networks = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Name of the libvirt network";
            };
            uuid = lib.mkOption {
              type = lib.types.str;
              description = "UUID for the libvirt network";
            };
            mode = lib.mkOption {
              type = lib.types.enum ["nat" "bridge" "isolated"];
              default = "nat";
              description = "Network mode for libvirt network";
            };
            bridge = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Bridge interface name (required for bridge mode)";
            };
            subnet = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Network subnet in CIDR notation (only for NAT/bridge modes)";
            };
            gateway = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Gateway IP address for the network (only for NAT/bridge modes)";
            };
            dhcpStart = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "DHCP start IP address (only for NAT/bridge modes)";
            };
            dhcpEnd = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "DHCP end IP address (only for NAT/bridge modes)";
            };
            firewallPorts = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  tcp = lib.mkOption {
                    type = lib.types.listOf lib.types.port;
                    default = [];
                    description = "TCP ports to allow through firewall for this network";
                  };
                  udp = lib.mkOption {
                    type = lib.types.listOf lib.types.port;
                    default = [];
                    description = "UDP ports to allow through firewall for this network";
                  };
                };
              };
              default = {
                tcp = [];
                udp = [];
              };
              description = "Firewall port configuration for this network";
            };
          };
        });
        default = [];
        description = "List of libvirt networks to create declaratively";
      };

      # Domain configuration options
      domains = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Name of the libvirt domain";
            };
            uuid = lib.mkOption {
              type = lib.types.str;
              description = "UUID for the libvirt domain";
            };
            template = lib.mkOption {
              type = lib.types.enum ["linux" "windows" "q35" "pc"];
              default = "linux";
              description = "Template to use for the domain";
            };
            memory = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  count = lib.mkOption {
                    type = lib.types.int;
                    default = 4;
                    description = "Memory amount";
                  };
                  unit = lib.mkOption {
                    type = lib.types.str;
                    default = "GiB";
                    description = "Memory unit";
                  };
                };
              };
              default = {
                count = 4;
                unit = "GiB";
              };
              description = "Memory configuration";
            };
            storageVol = lib.mkOption {
              type = lib.types.nullOr (lib.types.either lib.types.str lib.types.path);
              default = null;
              description = "Storage volume for the domain";
            };
            backingVol = lib.mkOption {
              type = lib.types.nullOr (lib.types.either lib.types.str lib.types.path);
              default = null;
              description = "Backing volume for the domain";
            };
            installVol = lib.mkOption {
              type = lib.types.nullOr (lib.types.either lib.types.str lib.types.path);
              default = null;
              description = "Installation ISO volume";
            };
            bridgeName = lib.mkOption {
              type = lib.types.str;
              default = "virbr0";
              description = "Network bridge to connect to";
            };
            virtioNet = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Use VirtIO for networking";
            };
            virtioVideo = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Use VirtIO for graphics";
            };
            virtioDrive = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Use VirtIO for storage";
            };
            nvramPath = lib.mkOption {
              type = lib.types.nullOr (lib.types.either lib.types.str lib.types.path);
              default = null;
              description = "NVRAM path (required for Windows template)";
            };
            installVirtio = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Add VirtIO drivers CDROM (for Windows)";
            };
            active = lib.mkOption {
              type = lib.types.nullOr lib.types.bool;
              default = null;
              description = "Whether the domain should be active (running)";
            };
            restart = lib.mkOption {
              type = lib.types.nullOr lib.types.bool;
              default = null;
              description = "Whether to restart the domain if definition changes";
            };
          };
        });
        default = [];
        description = "List of libvirt domains to create declaratively";
      };
    };

    config = lib.mkIf cfg.enable {
      virtualisation = {
        libvirt = {
          enable = true;
          verbose = true;
          swtpm.enable = true;
        };

        # Enable SPICE USB redirection if requested
        spiceUSBRedirection.enable = cfg.spiceUSBRedirection;

        # Configure networks using NixVirt templates
        libvirt.connections."qemu:///system" = {
          networks = lib.mkIf (cfg.networks != []) (
            map (network: {
              definition = inputs.NixVirt.lib.network.writeXML (
                if network.mode == "bridge"
                then
                  inputs.NixVirt.lib.network.templates.bridge {
                    inherit (network) uuid;
                    subnet_byte = lib.toInt (lib.last (lib.splitString "." network.gateway));
                  }
                else if network.mode == "isolated"
                then {
                  inherit (network) name;
                  inherit (network) uuid;
                  forward = {
                    mode = "none";
                  };
                  mac = {
                    address = "52:54:00:02:77:4b";
                  };
                  ip = {
                    address = "192.168.122.1";
                    netmask = "255.255.255.0";
                    dhcp = {
                      range = {
                        start = "192.168.122.2";
                        end = "192.168.122.254";
                      };
                    };
                  };
                }
                else {
                  inherit (network) name;
                  inherit (network) uuid;
                  forward = {
                    inherit (network) mode;
                    nat = lib.mkIf (network.mode == "nat") {
                      port = {
                        start = 1024;
                        end = 65535;
                      };
                    };
                  };
                  mac = {
                    address = "52:54:00:02:77:4b";
                  };
                  ip = {
                    address = network.gateway;
                    netmask = "255.255.255.0";
                    dhcp = {
                      range = {
                        start = network.dhcpStart;
                        end = network.dhcpEnd;
                      };
                    };
                  };
                }
              );
              active = true;
              restart = true;
            })
            cfg.networks
          );

          domains = lib.mkIf (cfg.domains != []) (
            map (domain: {
              definition = let
                templateFunc =
                  {
                    "linux" = inputs.NixVirt.lib.domain.templates.linux;
                    "windows" = inputs.NixVirt.lib.domain.templates.windows;
                    "q35" = inputs.NixVirt.lib.domain.templates.q35;
                    "pc" = inputs.NixVirt.lib.domain.templates.pc;
                  }.${
                    domain.template
                  };

                templateArgs =
                  {
                    inherit (domain) name;
                    inherit (domain) uuid;
                    inherit (domain) memory;
                    storage_vol = domain.storageVol;
                    backing_vol = domain.backingVol;
                    install_vol = domain.installVol;
                    bridge_name = domain.bridgeName;
                    virtio_net = domain.virtioNet;
                    virtio_video = domain.virtioVideo;
                    virtio_drive = domain.virtioDrive;
                  }
                  // lib.optionalAttrs (domain.template == "windows") {
                    nvram_path = domain.nvramPath;
                    install_virtio = domain.installVirtio;
                  };
              in
                inputs.NixVirt.lib.domain.writeXML (templateFunc templateArgs);
              inherit (domain) active;
              inherit (domain) restart;
            })
            cfg.domains
          );
        };

        # Allow bridges for qemu-bridge-helper
        libvirtd.allowedBridges = ["virbr0" "virbr1" "virbr2" "virbr3" "virbr4" "virbr5"];

        # libvirtd.nss = {
        #   enable = true;
        #   enableGuest = true;
        # };
      };

      environment.systemPackages = with pkgs; [
        dnsmasq
      ];

      # systemd service for VM shutdown on suspend
      systemd.services."libvirt-shutdown-vms-on-suspend" = lib.mkIf cfg.shutdownOnSuspend.enable {
        description = "Shutdown selected libvirt VMs on host suspend";
        wantedBy = ["sleep.target"];
        before = ["sleep.target"];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "shutdown-vms-on-suspend" ''
            timeout_per_vm=30

            shutdown_vm() {
              local vm="$1"
              echo "Requesting shutdown of $vm..."
              virsh shutdown "$vm" || true

              for i in $(seq 1 "$timeout_per_vm"); do
                state="$(virsh domstate "$vm" 2>/dev/null || true)"
                if [ "$state" != "running" ]; then
                  echo "$vm shut down gracefully."
                  return 0
                fi
                sleep 1
              done

              echo "$vm did not shut down in time, forcing destroy..."
              virsh destroy "$vm" || true
            }

            pids=()
            for vm in ${lib.escapeShellArgs cfg.shutdownOnSuspend.vms}; do
              shutdown_vm "$vm" &
              pids+=($!)
            done

            for pid in "''${pids[@]}"; do
              wait "$pid"
            done
          '';
        };
        path = [pkgs.libvirt];
      };

      # Firewall configuration for networks
      networking.firewall = {
        allowedTCPPorts = lib.concatLists (map (network: network.firewallPorts.tcp) cfg.networks);
        allowedUDPPorts = lib.concatLists (map (network: network.firewallPorts.udp) cfg.networks);
        # Add trusted interfaces for all network bridges
        trustedInterfaces = lib.mkIf (cfg.networks != []) (
          lib.unique (["virbr0"]
            ++ lib.concatLists (lib.imap0 (
                index: network:
                  if network.mode == "bridge" && network.bridge != null
                  then [network.bridge]
                  else ["virbr${toString (index + 1)}"]
              )
              cfg.networks))
        );
      };
    };
  };
}
