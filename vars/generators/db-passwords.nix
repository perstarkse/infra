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

      # NOTE: clan executes this script with a FRESH EMPTY $out and requires
      # every declared file, so every execution mints fresh passwords. clan
      # runs it only when a file is missing (or on explicit --regenerate);
      # never add a file here unless rotating both passwords is the intent.
      head -c 24 /dev/urandom | base64 | tr -d '\n' > "$out/politikerstod"
      head -c 24 /dev/urandom | base64 | tr -d '\n' > "$out/paperless"
      printf 'PAPERLESS_DBPASS=%s\n' "$(cat "$out/paperless")" > "$out/paperless.env"
    '';
    meta.tags = ["service" "db-passwords"];
  };
}
