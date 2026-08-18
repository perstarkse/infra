_: {
  config.flake.nixosModules.mosquitto = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.mosquitto;
  in {
    options.my.mosquitto = {
      enable = lib.mkEnableOption "Mosquitto MQTT broker";
      secretName = lib.mkOption {
        type = lib.types.str;
        default = "air-exhaust-mqtt";
        description = "clan-vars secret holding per-client credentials and password hashes.";
      };
      listeners = lib.mkOption {
        type = lib.types.listOf lib.types.attrs;
        default = [
          {
            address = "10.0.0.1";
            port = 1883;
            settings = {allow_anonymous = false;};
          }
        ];
        description = "Mosquitto listener definitions (LAN-only by default).";
      };
    };

    config = lib.mkIf cfg.enable {
      services.mosquitto = {
        enable = true;
        # Two clients per listener: `air-exhaust` for the exhaust-c6 ESP32
        # firmware and `hass` for the Home Assistant `mqtt:` integration.
        # Hashed passwords are generated once into the clan store (see the
        # secret below) and delivered as systemd credentials. Both clients
        # are scoped to the air-exhaust/# topic space.
        listeners = map (listener:
          listener
          // {
            users = {
              air-exhaust = {
                hashedPasswordFile = config.my.secrets.getPath cfg.secretName "air-exhaust.hash";
                acl = ["readwrite air-exhaust/#"];
              };
              hass = {
                hashedPasswordFile = config.my.secrets.getPath cfg.secretName "hass.hash";
                acl = ["readwrite air-exhaust/#"];
              };
            };
          })
        cfg.listeners;
      };

      # Random per-generation passwords, stored by clan so later deployments
      # reuse them. The *.env files carry the cleartext credentials: copy
      # air-exhaust.env into the ESP32 firmware's .env (MQTT_USERNAME /
      # MQTT_PASSWORD) and hass.env into Home Assistant's mqtt: block.
      my.secrets.declarations = [
        (config.my.secrets.mkSharedSecret {
          name = cfg.secretName;
          runtimeInputs = [pkgs.mosquitto pkgs.coreutils];
          files = {
            "air-exhaust.hash" = {mode = "0400";};
            "hass.hash" = {mode = "0400";};
            "air-exhaust.env" = {mode = "0400";};
            "hass.env" = {mode = "0400";};
          };
          script = ''
            air_pass="$(head -c 24 /dev/urandom | base64 -w0 | tr -d '/+=')"
            hass_pass="$(head -c 24 /dev/urandom | base64 -w0 | tr -d '/+=')"
            # mosquitto_passwd writes "user:<hash>"; strip the username.
            mosquitto_passwd -b -c "$out/air-exhaust.hash" air-exhaust "$air_pass"
            mosquitto_passwd -b -c "$out/hass.hash" hass "$hass_pass"
            line="$(head -1 "$out/air-exhaust.hash")"
            printf '%s' "''${line#*:}" > "$out/air-exhaust.hash"
            line="$(head -1 "$out/hass.hash")"
            printf '%s' "''${line#*:}" > "$out/hass.hash"
            printf 'username=air-exhaust\npassword=%s\n' "$air_pass" > "$out/air-exhaust.env"
            printf 'username=hass\npassword=%s\n' "$hass_pass" > "$out/hass.env"
          '';
        })
      ];
    };
  };
}
