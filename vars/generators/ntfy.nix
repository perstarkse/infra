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

      # Clan executes this generator with a FRESH EMPTY $out and requires
      # every declared file (clan_lib/vars/generator.py: `tmpdir_out` is a
      # new TemporaryDirectory; missing files are a hard error). There is
      # NO parse-back of the previous generation: `clan vars generate`
      # without `--regenerate` only runs generators with files missing
      # from the store (all_missing_closure), i.e. routine deploys never
      # re-run this script and never re-key publishers. An explicit
      # `--regenerate` (or a newly-added file like phone-token/phone-password
      # in 2026-09-21) re-runs it and MINTS EVERYTHING FRESH — including
      # all five per-topic tokens. So: never `--regenerate` this generator
      # (or add a file to it) unless re-keying every ntfy publisher is the
      # intent; coordinate with the io/makemake/sedna deploys that consume
      # the tokens. The same shape bit us on 2026-09-26: a regeneration
      # wrote a malformed env and sedna's ntfy-sh refused to start.
      keep_or_mint_token() {
        # $1 = file name under $out. Prints the kept token when the file
        # is already materialized, else mints a fresh one.
        local file="$1"
        if [ -s "$out/$file" ]; then
          tr -d '\n' < "$out/$file"
          return 0
        fi
        head -c 32 /dev/urandom | od -An -tx1 -v | tr -d ' \n' | cut -c1-29 | sed 's/^/tk_/'
      }

      # NOTE: no $out/env parse-back. $out starts empty on every execution,
      # so a PREV_ENV read here would always miss; a prior version quoted
      # the path as \"$PREV_ENV\" (literal quote characters in the
      # filename), which silently disabled even the fallback it intended.
      # Kept per-file values are the only keep signal. Absent files mean
      # first provision (or a new file added later) — mint fresh.

      storage_token="$(keep_or_mint_token storage-token)"
      backup_token="$(keep_or_mint_token backup-token)"
      indicator_token="$(keep_or_mint_token indicator-token)"
      heartbeat_token="$(keep_or_mint_token heartbeat-token)"
      phone_token="$(keep_or_mint_token phone-token)"

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

      # Fail closed: ntfy parses NTFY_AUTH_USERS strictly — one malformed
      # entry (2026-09-21: a 2-part phone-subscriber line plus token entries
      # folded into the users line, no TOKENS line at all) makes ntfy-sh
      # exit 1 and the alert path goes silent. Validate the assembled env
      # here, at generate time, instead of on sedna at deploy time.
      bad_users="$(grep '^NTFY_AUTH_USERS=' "$out/env" | tr ',' '\n' | grep -v -c '^[^:]*:[^:]*:[^:]*$' || true)"
      users_lines="$(grep -c '^NTFY_AUTH_USERS=' "$out/env" || true)"
      tokens_lines="$(grep -c '^NTFY_AUTH_TOKENS=' "$out/env" || true)"
      bad_tokens="$(grep '^NTFY_AUTH_TOKENS=' "$out/env" | tr ',' '\n' | grep -v -c '^[^:]*:[^:]*:[^:]*$' || true)"
      if [ "$users_lines" != 1 ] || [ "$tokens_lines" != 1 ] || [ "$bad_users" != 0 ] || [ "$bad_tokens" != 0 ]; then
        printf '%s\n' "ntfy generator: malformed env (users_lines=$users_lines tokens_lines=$tokens_lines bad_users=$bad_users bad_tokens=$bad_tokens)" >&2
        exit 1
      fi
    '';
    meta.tags = ["service" "ntfy"];
  };
}
