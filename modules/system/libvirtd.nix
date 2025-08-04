{
  config.flake.nixosModules.libvirtd = {
    lib,
    config,
    pkgs,
    ...
  }: let
    cfg = config.my.libvirtd;
    
    # Helper function to convert CIDR to netmask
    cidrToNetmask = cidr: let
      parts = lib.splitString "/" cidr;
      prefix = toString (lib.last parts);
      netmaskMap = {
        "8" = "255.0.0.0";
        "16" = "255.255.0.0";
        "24" = "255.255.255.0";
        "25" = "255.255.255.128";
        "26" = "255.255.255.192";
        "27" = "255.255.255.224";
        "28" = "255.255.255.240";
        "29" = "255.255.255.248";
        "30" = "255.255.255.252";
        "31" = "255.255.255.254";
        "32" = "255.255.255.255";
      };
    in netmaskMap.${prefix} or "255.255.255.0";
  in {
    options.my.libvirtd = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable libvirtd with dnsmasq DHCP support.";
      };
      
      # Network configuration options
      networks = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Name of the libvirt network";
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
            device = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Physical device for macvtap mode";
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
    };

    config = lib.mkIf cfg.enable {
      virtualisation.libvirtd = {
        enable = true;
        qemu = {
          ovmf.enable = true;
          runAsRoot = false;
          package = pkgs.qemu_kvm;
          verbatimConfig = ''
            cgroup_controllers = [ "cpu", "memory", "blkio", "cpuset", "cpuacct" ]
          '';
        };
        onBoot = "ignore";
        onShutdown = "shutdown";
      };
      
      # Create declarative networks
      systemd.services = lib.mkIf (cfg.networks != []) (
        lib.listToAttrs (map (network: 
          lib.nameValuePair "libvirt-network-${network.name}" {
            description = "Create libvirt network ${network.name}";
            wantedBy = ["multi-user.target"];
            after = ["libvirtd.service"];
            requires = ["libvirtd.service"];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = let
                networkXml = pkgs.writeText "network-${network.name}.xml" ''
                  <network>
                    <name>${network.name}</name>
                    <forward mode="${network.mode}"/>
                    ${lib.optionalString (network.mode == "bridge") ''
                    <bridge name="${network.bridge}"/>
                    ''}
                    ${lib.optionalString (network.mode != "bridge" && network.gateway != null) ''
                    <ip address="${network.gateway}" netmask="${cidrToNetmask network.subnet}">
                      <dhcp>
                        <range start="${network.dhcpStart}" end="${network.dhcpEnd}"/>
                      </dhcp>
                    </ip>
                    ''}
                  </network>
                '';
              in "${pkgs.bash}/bin/bash -c '${pkgs.libvirt}/bin/virsh net-list --name | grep -q \"^${network.name}$\" || (${pkgs.libvirt}/bin/virsh net-define ${networkXml} && echo \"Network ${network.name} defined successfully\"); ${pkgs.libvirt}/bin/virsh net-start ${network.name} && echo \"Network ${network.name} started successfully\"; ${pkgs.libvirt}/bin/virsh net-autostart ${network.name} && echo \"Network ${network.name} autostart enabled\"'";
              ExecStop = "${pkgs.libvirt}/bin/virsh net-destroy ${network.name}";
              ExecStopPost = "${pkgs.libvirt}/bin/virsh net-undefine ${network.name}";
            };
          }
        ) cfg.networks)
      );

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
    };
  };
} 