{lib}: {config, ...}: let
  inherit (config.lib.topology) mkConnection mkInternet mkSwitch;
in {
  networks = {
    heliosphere = {
      name = "Heliosphere LAN";
      cidrv4 = "10.0.0.0/24";
      style = {
        primaryColor = "#f1cf8a";
        secondaryColor = null;
        pattern = "solid";
      };
    };

    upstream = {
      name = "Upstream";
      style = {
        primaryColor = "#70a5eb";
        secondaryColor = null;
        pattern = "dashed";
      };
    };

    cameras = {
      name = "Cameras";
      cidrv4 = "10.0.30.0/24";
      style = {
        primaryColor = "#e05f65";
        secondaryColor = null;
        pattern = "dashed";
      };
    };

    wireguard = {
      name = "WireGuard";
      cidrv4 = "10.6.0.0/24";
      style = {
        primaryColor = "#78dba9";
        secondaryColor = null;
        pattern = "dotted";
      };
    };
  };

  # Rendering all aggregated service cards can be very slow on large hosts.
  renderers.elk.overviews.services.enable = false;
  renderers.elk.overviews.networks.enable = false;

  nodes = {
    internet =
      (mkInternet {
        connections = mkConnection "io" "enp1s0";
      })
      // {
        icon = null;
        deviceIcon = null;
        renderer.preferredType = "card";
        hardware = {
          image = null;
          info = "WAN";
        };
      };

    io = {
      icon = null;
      deviceIcon = null;
      renderer.preferredType = "card";
      hardware.image = null;
      hardware.info = "Router";
      interfaces = lib.mkForce {
        enp1s0.network = "upstream";
        br-lan = {
          network = "heliosphere";
          addresses = ["10.0.0.1"];
          physicalConnections = [
            (mkConnection "switch-main" "uplink")
          ];
        };
        vlan30 = {
          network = "cameras";
          addresses = ["10.0.30.1"];
        };
        wg0 = {
          network = "wireguard";
          addresses = ["10.6.0.1"];
          virtual = true;
          type = "wireguard";
          renderer.hidePhysicalConnections = true;
        };
      };
    };

    switch-main = mkSwitch "Main Switch" {
      icon = null;
      deviceIcon = null;
      info = "Ubiquiti USW";
      image = null;
      interfaceGroups = [["uplink" "port1" "port2" "port3" "port4"]];
      connections = {
        uplink = mkConnection "io" "br-lan";
        port1 = mkConnection "charon" "enp4s0";
        port2 = mkConnection "ariel" "enp3s0f1";
        port3 = mkConnection "oumuamua" "enp8s0";
        port4 = mkConnection "makemake" "lan";
      };
    };

    charon = {
      icon = null;
      deviceIcon = null;
      renderer.preferredType = "card";
      hardware.image = null;
      hardware.info = "Workstation";
      interfaces = lib.mkForce {
        enp4s0 = {};
      };
    };

    ariel = {
      icon = null;
      deviceIcon = null;
      renderer.preferredType = "card";
      hardware.image = null;
      hardware.info = "Laptop";
      interfaces = lib.mkForce {
        enp3s0f1 = {};
      };
    };

    oumuamua = {
      icon = null;
      deviceIcon = null;
      renderer.preferredType = "card";
      hardware.image = null;
      hardware.info = "Server";
      interfaces = lib.mkForce {
        enp8s0 = {};
      };
    };

    # makemake currently does not expose interface details to topology extractors,
    # so we define a logical LAN interface explicitly.
    makemake = {
      icon = null;
      deviceIcon = null;
      renderer.preferredType = "card";
      hardware.image = null;
      hardware.info = "Server";
      interfaces = {
        lan = {
          network = "heliosphere";
          addresses = ["10.0.0.10/24"];
        };
      };
    };
  };
}
