_: {
  config.flake.nixosModules.mosquitto = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.mosquitto;
    hashFiles = [
      (config.my.secrets.getPath cfg.secretName "air-exhaust.hash")
      (config.my.secrets.getPath cfg.secretName "hass.hash")
      (config.my.secrets.getPath cfg.secretName "charon-ro.hash")
    ];
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
        # Three clients per listener: `air-exhaust` for the exhaust-c6 ESP32
        # firmware, `hass` for the Home Assistant `mqtt:` integration, and
        # `charon-ro` for the read-only Noctalia bar widget on charon.
        # Hashed passwords are generated once into the clan store (generator:
        # vars/generators/air-exhaust-mqtt.nix, discovered by tag) and
        # delivered as systemd credentials. All share the `air-exhaust/#`
        # topic space for the fan control/status loops.
        #
        # HA MQTT discovery needs two extra ACL grants: the firmware publishes
        # retained discovery configs under `homeassistant/sensor/...` (so it
        # must be able to write there), and the hass integration subscribes to
        # `homeassistant/#` to create entities from them (so it must be able
        # to read there). Scope both as narrowly as possible.
        #
        # MQTT wildcards must be a whole level, so a prefix-scoped
        # `homeassistant/sensor/exhaust_c6_#` is invalid (the firmware's
        # discovery topics are `homeassistant/sensor/exhaust_c6_{duty,rpm,
        # room,mode}/config`); `homeassistant/sensor/#` is the narrowest valid
        # pattern that still matches them.
        listeners = map (listener:
          listener
          // {
            users = {
              air-exhaust = {
                hashedPasswordFile = config.my.secrets.getPath cfg.secretName "air-exhaust.hash";
                acl = [
                  "readwrite air-exhaust/#"
                  "write homeassistant/sensor/#"
                ];
              };
              hass = {
                hashedPasswordFile = config.my.secrets.getPath cfg.secretName "hass.hash";
                acl = [
                  "readwrite air-exhaust/#"
                  "read homeassistant/#"
                ];
              };
              charon-ro = {
                hashedPasswordFile = config.my.secrets.getPath cfg.secretName "charon-ro.hash";
                acl = [
                  "read air-exhaust/fan/status"
                ];
              };
            };
          })
        cfg.listeners;
      };

      # Passwords are generated once by vars/generators/air-exhaust-mqtt.nix
      # (shared values, stored by clan so later deployments reuse them). The
      # *.env files carry the cleartext credentials: copy air-exhaust.env
      # into the ESP32 firmware's .env (MQTT_USERNAME / MQTT_PASSWORD) and
      # hass.env into Home Assistant's mqtt: block. charon-ro.env is exposed
      # to user p on charon for the Noctalia widget.
      #
      # Mosquitto loads the password files only at startup: a secret content
      # change (clan vars re-deploy) must restart it or it keeps serving the
      # pre-rotation hashes and refuses every client. The unit is
      # byte-identical across such deploys (same paths, same ACLs), so
      # restartTriggers on the hash paths are inert strings that never fire —
      # hence the path watcher below, which restarts mosquitto whenever any
      # hash file actually changes on disk.
      systemd.paths.mosquitto-hash-rotation = {
        description = "Restart mosquitto when its password hashes rotate";
        wantedBy = ["multi-user.target"];
        pathConfig = {
          PathChanged = hashFiles;
          Unit = "mosquitto-hash-rotation-restart.service";
        };
      };

      systemd.services.mosquitto-hash-rotation-restart = {
        description = "Restart mosquitto after password hash rotation";
        serviceConfig = {
          Type = "oneshot";
          # Let a multi-file write batch settle: clan writes the three
          # hashes in quick succession, and one restart must see all of them.
          ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
          ExecStart = "${pkgs.systemd}/bin/systemctl restart mosquitto.service";
        };
      };
    };
  };
}
