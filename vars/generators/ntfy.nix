{pkgs, ...}: {
  "ntfy" = {
    share = true;
    runtimeInputs = [pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.openssl (pkgs.python3.withPackages (ps: [ps.bcrypt]))];
    files = {
      env = {
        mode = "0400";
        neededFor = "services";
      };
      storage-token = {
        mode = "0400";
        neededFor = "services";
      };
      backup-token = {
        mode = "0400";
        neededFor = "services";
      };
      indicator-token = {
        mode = "0400";
        neededFor = "services";
      };
      heartbeat-token = {
        mode = "0400";
        neededFor = "services";
      };
      # Per-device read-only credential for off-LAN subscribers (phone on
      # 5G, no VPN). Anonymous read stays CLOSED: NTFY_AUTH_DEFAULT_ACCESS
      # is deny-all and the canonical ACL grants *:ro to nobody.
      # phone-token: access token for API/Bearer clients. phone-password:
      # the iOS app's Basic-auth password for the same phone-subscriber
      # account (iOS has no token-login field; username is mandatory).
      phone-token = {
        mode = "0400";
        neededFor = "services";
      };
      phone-password = {
        mode = "0400";
        neededFor = "services";
      };
    };
    # NOTE: no prompts stanza. A phone_password prompt existed briefly
    # (2026-09-21) but clan never persists prompt answers into the store —
    # `clan vars list` showed ntfy/phone_password as <not set> forever, so
    # every `machines update` re-asked it. The phone-password FILE below
    # persists through the normal file mechanism and is the single source
    # of truth; rotation = `clan vars set sedna ntfy/phone-password`.
    script = ''
      set -euo pipefail
      umask 077
      mkdir -p "$out"

      # Canonical ACL — gated access (no anonymous read):
      # - storage-publisher:wo storage-alerts (Garage storage alerts)
      # - backup-publisher:wo backup-alerts (backup failure notify)
      # - indicator-publisher:wo indicator-alerts (indicator daemon)
      # - heartbeat-publisher:wo heartbeat (heartbeat push failure alerts)
      # - phone-subscriber:ro on all four topics (per-device credential)
      canonical_access='storage-publisher:storage-alerts:wo,backup-publisher:backup-alerts:wo,indicator-publisher:indicator-alerts:wo,heartbeat-publisher:heartbeat:wo,phone-subscriber:storage-alerts:ro,phone-subscriber:backup-alerts:ro,phone-subscriber:indicator-alerts:ro,phone-subscriber:heartbeat:ro'

      fallback_hash='$2b$10$QqZS0iP8PwNX1ddWX7ynCeLKM72wyx1PQYUt8sOd08mXQIQwe8U9G'

      # Every per-topic token below is a clan FILE output ($out/<name>), so
      # clan persists each value independently across regenerations. The
      # generator only mints a token when its file has no kept value AND the
      # previous env carries none — deployed publishers are never silently
      # re-keyed (2026-09-21: prompt-env parse-back missed tokens when the
      # NTFY_AUTH_TOKENS line was absent, and the hard-require guard fired
      # on a healthy provision).
      keep_or_mint_token() {
        # $1 = file name under $out, $2 = username, $3 = topic scope
        # Prints the token on stdout.
        local file="$1" user="$2" scope="$3" prev=""
        if [ -s "$out/$file" ]; then
          tr -d '\n' < "$out/$file"
          return 0
        fi
        if [ -n "''${PREV_ENV:-}" ] && [ -s "$PREV_ENV" ]; then
          prev="$(grep -o 'NTFY_AUTH_TOKENS=.*' \"$PREV_ENV\" | tr ',' '\n' | grep \"^$user:\" | head -n 1 | cut -d: -f2)"
        fi
        if [ -n "$prev" ]; then
          printf '%s' "$prev"
        else
          head -c 32 /dev/urandom | od -An -tx1 -v | tr -d ' \n' | cut -c1-29 | sed 's/^/tk_/'
        fi
      }

      # Previous provisioned env, when clan hands us the current generation:
      # $out/env pre-exists (kept outputs are materialized before the script
      # runs). Absent on first provision — then everything is minted fresh.
      if [ -s "$out/env" ]; then
        PREV_ENV="$out/env"
      else
        PREV_ENV=""
      fi

      storage_token="$(keep_or_mint_token storage-token storage-publisher storage-alerts)"
      backup_token="$(keep_or_mint_token backup-token backup-publisher backup-alerts)"
      indicator_token="$(keep_or_mint_token indicator-token indicator-publisher indicator-alerts)"
      heartbeat_token="$(keep_or_mint_token heartbeat-token heartbeat-publisher heartbeat)"
      phone_token="$(keep_or_mint_token phone-token phone-subscriber '*')"

      # Phone password: the kept $out/phone-password file wins, else
      # auto-generate. Never reuses a token. (No prompt: clan does not
      # persist prompt answers, so a phone_password prompt re-asked on
      # every update — file persistence is the single source of truth.)
      if [ -s "$out/phone-password" ]; then
        phone_password="$(cat "$out/phone-password")"
      else
        phone_password="$(head -c 18 /dev/urandom | openssl enc -base64 -A | tr -d '\n')"
      fi
      rm -f "$out/phone-password"
      printf '%s' "$phone_password" > "$out/phone-password"
      chmod 0400 "$out/phone-password"
      # ntfy needs $2b$ (not $2y$) bcrypt; python bcrypt emits $2b$.
      # NOTE: no heredoc anywhere in this script — clan wraps generators
      # for bwrap and mangles heredoc delimiters (seen 2026-09-21: exit 2).
      # Single python3 -c strings + env-passing only.
      phone_hash="$(python3 -c 'import sys,bcrypt; print(bcrypt.hashpw(sys.argv[1].encode(), bcrypt.gensalt(10)).decode())' "$phone_password")"

      {
        printf '%s\n' 'NTFY_AUTH_FILE=/var/lib/ntfy-sh/user.db'
        printf '%s\n' 'NTFY_AUTH_DEFAULT_ACCESS=deny-all'
        printf '%s\n' "NTFY_AUTH_USERS=storage-publisher:$fallback_hash:user,backup-publisher:$fallback_hash:user,indicator-publisher:$fallback_hash:user,heartbeat-publisher:$fallback_hash:user,phone-subscriber:$phone_hash:user"
        printf '%s\n' "NTFY_AUTH_ACCESS=$canonical_access"
        printf '%s\n' "NTFY_AUTH_TOKENS=storage-publisher:$storage_token:storage-alerts,backup-publisher:$backup_token:backup-alerts,indicator-publisher:$indicator_token:indicator-alerts,heartbeat-publisher:$heartbeat_token:heartbeat,phone-subscriber:$phone_token:*"
      } > "$out/env"

      printf '%s\n' "$storage_token" > "$out/storage-token"
      printf '%s\n' "$backup_token" > "$out/backup-token"
      printf '%s\n' "$indicator_token" > "$out/indicator-token"
      printf '%s\n' "$heartbeat_token" > "$out/heartbeat-token"
      printf '%s\n' "$phone_token" > "$out/phone-token"
    '';
    meta.tags = ["service" "ntfy"];
  };
}
