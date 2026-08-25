{
  config.flake.nixosModules.home-assistant = {
    config,
    lib,
    mkStandardEndpointsOptions,
    ...
  }: let
    cfg = config.my.home-assistant;
  in {
    options.my.home-assistant = {
      enable = lib.mkEnableOption "Home Assistant container";
      endpoints = mkStandardEndpointsOptions {
        subject = "Home Assistant";
        visibility = "internal";
      };
    };

    config = lib.mkIf cfg.enable {
      systemd.tmpfiles.rules = [
        "d /data/.state/home-assistant 0755 root root - -"
      ];
      # Note (2026-08-18): neither HTTP reverse-proxy trust
      # (use_x_forwarded_for / trusted_proxies) nor the MQTT broker wiring
      # belongs in configuration.yaml on HA 2026.8+: the former lives in
      # .storage/http (Settings > System > Network) and the latter is a config
      # entry in .storage/core.config_entries. A YAML `mqtt: broker: ...` block
      # is INVALID config on 2026.8 (mqtt setup fails, which also takes down
      # frigate since it depends on mqtt), and the http block is ignored after
      # migration. Do not re-add YAML blocks here.
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

      my.endpoints.services.home-assistant = lib.mkIf config.my.home-assistant.endpoints.enable {
        upstream = {
          host = config.my.listenNetworkAddress;
          port = 8123;
        };
        http.virtualHosts = lib.optional (config.my.home-assistant.endpoints.domain != null) {
          inherit (config.my.home-assistant.endpoints) domain;
          inherit (config.my.home-assistant.endpoints) lanOnly useWildcard;
        };
        firewall.local = {
          enable = true;
          tcp = [8123 1400];
        };
      };

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
          # Pinned deliberately: podman's default pull policy is "missing", so
          # `:stable` never re-pulled and the container silently ran a 14-month-
          # old image (2025.6.1/py3.13) until 2026-08-18. Bump this tag together
          # with the frigate (>= 5.15.4 on py3.14) and plejd (>= 0.20.x)
          # component versions.
          image = "ghcr.io/home-assistant/home-assistant:2026.8.2";
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
