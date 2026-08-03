{pkgs, ...}: {
  "db-passwords" = {
    share = true;
    runtimeInputs = [pkgs.coreutils];
    files = {
      "politikerstod" = {
        mode = "0400";
        neededFor = "services";
      };
      "paperless" = {
        mode = "0400";
        neededFor = "services";
      };
      "paperless.env" = {
        mode = "0400";
        neededFor = "services";
      };
    };
    script = ''
      set -euo pipefail
      umask 077
      mkdir -p "$out"

      # Idempotent: keep existing passwords on regeneration.
      if [ ! -s "$out/politikerstod" ]; then
        head -c 24 /dev/urandom | base64 | tr -d '\n' > "$out/politikerstod"
      fi
      if [ ! -s "$out/paperless" ]; then
        head -c 24 /dev/urandom | base64 | tr -d '\n' > "$out/paperless"
      fi
      printf 'PAPERLESS_DBPASS=%s\n' "$(cat "$out/paperless")" > "$out/paperless.env"
    '';
    meta.tags = ["service" "db-passwords"];
  };
}
