{pkgs, ...}: {
  # Shared broker credentials for the air-exhaust MQTT topic space.
  # Discovered by io (mosquitto service, services scope) and charon
  # (Noctalia widget via exposeUserSecrets, users scope); share = true keeps
  # the values identical on both. Previously declared inline in
  # modules/system/mosquitto.nix, which io alone evaluates — charon never saw
  # the generator, so `clan machines update` deployed the secrets to io only.
  "air-exhaust-mqtt" = {
    share = true;
    runtimeInputs = [pkgs.mosquitto pkgs.coreutils];
    files = {
      "air-exhaust.hash" = {mode = "0400";};
      "hass.hash" = {mode = "0400";};
      "charon-ro.hash" = {mode = "0400";};
      "air-exhaust.env" = {mode = "0400";};
      "hass.env" = {mode = "0400";};
      "charon-ro.env" = {
        mode = "0400";
        # Users scope so clan deploys it to /run/secrets-for-users/vars/...,
        # where charon's expose unit copies it to ~/.config/air-exhaust/.
        neededFor = "users";
      };
    };
    # Idempotent: each file is generated only when absent, so re-running this
    # generator (e.g. while deploying an unrelated secret) never rotates the
    # fan/HA credentials out from under the firmware (compiled-in) and HA
    # (config entry) — the failure mode that broke every consumer repeatedly.
    # Deliberate rotation: `clan vars generate <m> --generator
    # air-exhaust-mqtt --regenerate`, then restart mosquitto and refresh the
    # firmware / HA / widget credentials.
    script = ''
      set -euo pipefail
      umask 077
      mkdir -p "$out"

      # $1 = username, $2 = output base ("*.hash"). Writes "$2" (bcrypt hash
      # only) and "$(basename $2 .hash).env" (username= / password= cleartext
      # for the firmware .env and HA) — but only when the hash is absent.
      gen() {
        if [ -f "$out/$2" ]; then
          return
        fi
        p="$(head -c 24 /dev/urandom | base64 -w0 | tr -d '/+=')"
        # mosquitto_passwd writes "user:<hash>"; strip the username.
        mosquitto_passwd -b -c "$out/.tmp-$2" "$1" "$p"
        line="$(head -1 "$out/.tmp-$2")"
        printf '%s' "''${line#*:}" > "$out/$2"
        rm -f "$out/.tmp-$2"
        envf="$out/''${2%.hash}.env"
        printf 'username=%s\npassword=%s\n' "$1" "$p" > "$envf"
      }

      gen air-exhaust air-exhaust.hash
      gen hass hass.hash
      gen charon-ro charon-ro.hash
    '';
    meta = {
      tags = ["air-exhaust-mqtt"];
    };
  };
}
