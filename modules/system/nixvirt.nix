{ inputs, ... }: {
  config.flake.nixosModules.nixvirt = {
    lib,
    config,
    pkgs,
    ...
  }: let
    cfg = config.my.nixvirt;
  in {
    options.my.nixvirt = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable NixVirt for declarative libvirt management.";
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
              default = { count = 4; unit = "GiB"; };
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
      # Enable NixVirt
      virtualisation.libvirt = {
        enable = true;
        verbose = true;
        swtpm.enable = true;
      };

      # Configure networks
      virtualisation.libvirt.connections."qemu:///system" = {
        networks = lib.mkIf (cfg.networks != []) (
          map (network: {
            definition = inputs.NixVirt.lib.network.writeXML {
              name = network.name;
              uuid = network.uuid;
              forward = {
                mode = network.mode;
                nat = lib.mkIf (network.mode == "nat") {
                  port = { start = 1024; end = 65535; };
                };
              };
              bridge = lib.mkIf (network.mode == "bridge") {
                name = network.bridge;
              };
              mac = {
                address = "52:54:00:02:77:4b";
              };
              ip = lib.mkIf (network.gateway != null) {
                address = network.gateway;
                netmask = "255.255.255.0";
                dhcp = {
                  range = {
                    start = network.dhcpStart;
                    end = network.dhcpEnd;
                  };
                };
              };
            };
            active = true;
            restart = true;
          }) cfg.networks
        );

        domains = lib.mkIf (cfg.domains != []) (
          map (domain: {
            definition = let
              templateFunc = {
                "linux" = inputs.NixVirt.lib.domain.templates.linux;
                "windows" = inputs.NixVirt.lib.domain.templates.windows;
                "q35" = inputs.NixVirt.lib.domain.templates.q35;
                "pc" = inputs.NixVirt.lib.domain.templates.pc;
              }.${domain.template};
              
              templateArgs = {
                name = domain.name;
                uuid = domain.uuid;
                memory = domain.memory;
                storage_vol = domain.storageVol;
                backing_vol = domain.backingVol;
                install_vol = domain.installVol;
                bridge_name = domain.bridgeName;
                virtio_net = domain.virtioNet;
                virtio_video = domain.virtioVideo;
                virtio_drive = domain.virtioDrive;
              } // lib.optionalAttrs (domain.template == "windows") {
                nvram_path = domain.nvramPath;
                install_virtio = domain.installVirtio;
              };
            in inputs.NixVirt.lib.domain.writeXML (templateFunc templateArgs);
            active = domain.active;
            restart = domain.restart;
          }) cfg.domains
        );
      };

      # Firewall configuration for networks
      networking.firewall = {
        allowedTCPPorts = lib.concatLists (map (network: network.firewallPorts.tcp) cfg.networks);
        allowedUDPPorts = lib.concatLists (map (network: network.firewallPorts.udp) cfg.networks);
      };

      # Create bridge interfaces for bridge mode networks
      systemd.network = lib.mkIf (cfg.networks != []) {
        enable = true;
        netdevs = lib.listToAttrs (
          lib.filter (x: x != null) (
            map (network: 
              if network.mode == "bridge" && network.bridge != null then
                lib.nameValuePair "br-${network.bridge}" {
                  netdevConfig = {
                    Kind = "bridge";
                    Name = network.bridge;
                  };
                }
              else null
            ) cfg.networks
          )
        );
        networks = lib.listToAttrs (
          lib.filter (x: x != null) (
            map (network: 
              if network.mode == "bridge" && network.bridge != null then
                lib.nameValuePair "br-${network.bridge}" {
                  matchConfig.Name = network.bridge;
                  address = ["${network.gateway}/${lib.last (lib.splitString "/" network.subnet)}"];
                  networkConfig = {
                    ConfigureWithoutCarrier = true;
                  };
                  bridgeConfig = {};
                  linkConfig.RequiredForOnline = "no";
                }
              else null
            ) cfg.networks
          )
        );
      };

      # Allow bridges for qemu-bridge-helper
      virtualisation.libvirtd.allowedBridges = 
        lib.mkIf (cfg.networks != []) 
        (lib.unique (lib.filter (x: x != null) (map (network: network.bridge) cfg.networks)));
    };
  };
} 