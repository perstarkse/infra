{
  config.flake.nixosModules.home-assistant = {
    config = {
      systemd.tmpfiles.rules = [
        "d /data/.state/home-assistant 0755 root root - -"
      ];

      # System requirements for bluetooth
      services.dbus.enable = true;
      hardware.bluetooth.enable = true;
      services.blueman.enable = true;

      networking.firewall.allowedTCPPorts = [8123 1400];

      virtualisation.oci-containers = {
        containers.homeassistant = {
          volumes = [
            "/data/.state/home-assistant:/config"
            "/run/dbus:/run/dbus:ro"
          ];
          environment = {
            TZ = "Europe/Berlin";
            DBUS_SYSTEM_BUS_ADDRESS = "unix:path=/run/dbus/system_bus_socket";
          };
          image = "ghcr.io/home-assistant/home-assistant:stable";
          extraOptions = [
            "--network=host"
            "--device=/dev/conbee:/dev/conbee"
            "--device=/dev/bluetooth_dongle:/dev/bluetooth_dongle"
            "--privileged"
          ];
        };
      };

      # Persistent device rules
      services.udev.extraRules = ''
        SUBSYSTEM=="tty", ATTRS{idVendor}=="1cf1", ATTRS{idProduct}=="0030", SYMLINK+="conbee", MODE="0666"
        SUBSYSTEM=="usb", ATTRS{idVendor}=="0a12", ATTRS{idProduct}=="0001", SYMLINK+="bluetooth_dongle", MODE="0666"
      '';
    };
  };
}
