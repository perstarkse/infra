{
  config.flake.nixosModules.home-assistant = {pkgs, ...}: {
    config = {
      systemd = {
        tmpfiles.rules = [
          "d /data/.state/home-assistant 0755 root root - -"
        ];
        services.homeassistant-reverse-proxy-config = {
          description = "Ensure Home Assistant trusts local reverse proxy";
          before = ["podman-homeassistant.service"];
          serviceConfig.Type = "oneshot";
          script = ''
            set -eu

            cfg=/data/.state/home-assistant/configuration.yaml

            if [ ! -f "$cfg" ]; then
              cat > "$cfg" <<'EOF'
            # Loads default set of integrations. Do not remove.
            default_config:

            # Load frontend themes from the themes folder
            frontend:
              themes: !include_dir_merge_named themes

            automation: !include automations.yaml
            script: !include scripts.yaml
            scene: !include scenes.yaml
            EOF
            fi

            if ! ${pkgs.gnugrep}/bin/grep -q "use_x_forwarded_for:" "$cfg"; then
              cat >> "$cfg" <<'EOF'

            http:
              use_x_forwarded_for: true
              trusted_proxies:
                - 10.0.0.1
                - 127.0.0.1
                - ::1
            EOF
            fi
          '';
        };
        services.podman-homeassistant = {
          requires = ["homeassistant-reverse-proxy-config.service"];
          after = ["homeassistant-reverse-proxy-config.service"];
        };
      };
      services = {
        # System requirements for bluetooth
        dbus.enable = true;
        blueman.enable = true;

        # Persistent device rules
        udev.extraRules = ''
          SUBSYSTEM=="tty", ATTRS{idVendor}=="1cf1", ATTRS{idProduct}=="0030", SYMLINK+="conbee", MODE="0666"
          SUBSYSTEM=="usb", ATTRS{idVendor}=="0a12", ATTRS{idProduct}=="0001", SYMLINK+="bluetooth_dongle", MODE="0666"
        '';
      };
      hardware.bluetooth.enable = true;

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
    };
  };
}
