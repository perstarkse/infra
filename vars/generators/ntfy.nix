{pkgs, ...}: {
  "ntfy" = {
    share = true;
    runtimeInputs = [pkgs.coreutils pkgs.gnugrep];
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
    };
    prompts = {
      env = {
        description = "Optional ntfy env file (KEY=VALUE). If omitted, a minimal ntfy config with auto-generated storage tokens is created.";
        persist = true;
        type = "hidden";
      };
    };
    script = ''
            set -euo pipefail
            umask 077
            mkdir -p "$out"

            _prompts_dir="''${prompts:-}"
            if [ -z "$_prompts_dir" ] || [ ! -d "$_prompts_dir" ]; then
              _prompts_dir=""
            fi

            # Canonical ACL — write topics are token-only, reads stay anonymous
            # (phone subscribers):
            # - storage-publisher:wo storage-alerts (Garage storage alerts)
            # - backup-publisher:wo backup-alerts (backup failure notify)
            # - indicator-publisher:wo indicator-alerts (indicator daemon)
            # - *:ro on all three topics for subscribers
            canonical_access='storage-publisher:storage-alerts:wo,backup-publisher:backup-alerts:wo,indicator-publisher:indicator-alerts:wo,*:storage-alerts:ro,*:backup-alerts:ro,*:indicator-alerts:ro'

            storage_token=""
            backup_token=""
            indicator_token=""
            has_storage_user=""
            has_backup_user=""
            has_indicator_user=""
            fallback_storage_hash='$2b$10$QqZS0iP8PwNX1ddWX7ynCeLKM72wyx1PQYUt8sOd08mXQIQwe8U9G'
            fallback_backup_hash='$2b$10$QqZS0iP8PwNX1ddWX7ynCeLKM72wyx1PQYUt8sOd08mXQIQwe8U9G'
            fallback_indicator_hash='$2b$10$QqZS0iP8PwNX1ddWX7ynCeLKM72wyx1PQYUt8sOd08mXQIQwe8U9G'

            if [ -n "$_prompts_dir" ] && [ -s "$_prompts_dir/env" ]; then
              cp "$_prompts_dir/env" "$out/env"

              while IFS= read -r line; do
                case "$line" in
                  NTFY_AUTH_USERS=*)
                    users_value="''${line#NTFY_AUTH_USERS=}"
                    old_ifs="$IFS"
                    IFS=,
                    set -- $users_value
                    IFS="$old_ifs"

                    for entry in "$@"; do
                      case "$entry" in
                        storage-publisher:*:user|storage-publisher:*:admin)
                          has_storage_user=1
                          ;;
                        backup-publisher:*:user|backup-publisher:*:admin)
                          has_backup_user=1
                          ;;
                        indicator-publisher:*:user|indicator-publisher:*:admin)
                          has_indicator_user=1
                          ;;
                      esac
                    done
                    ;;
                  NTFY_AUTH_TOKENS=*)
                    tokens_value="''${line#NTFY_AUTH_TOKENS=}"
                    old_ifs="$IFS"
                    IFS=,
                    set -- $tokens_value
                    IFS="$old_ifs"

                    for entry in "$@"; do
                      case "$entry" in
                        storage-publisher:*:storage-alerts)
                          rest="''${entry#storage-publisher:}"
                          storage_token="''${rest%%:storage-alerts}"
                          ;;
                        backup-publisher:*:backup-alerts)
                          rest="''${entry#backup-publisher:}"
                          backup_token="''${rest%%:backup-alerts}"
                          ;;
                        indicator-publisher:*:indicator-alerts)
                          rest="''${entry#indicator-publisher:}"
                          indicator_token="''${rest%%:indicator-alerts}"
                          ;;
                      esac
                    done
                    ;;
                esac
              done < "$out/env"

              if [ -z "$has_storage_user" ] || [ -z "$has_backup_user" ] || [ -z "$has_indicator_user" ]; then
                printf '%s\n' 'ntfy env prompt must define NTFY_AUTH_USERS for storage-publisher, backup-publisher and indicator-publisher' >&2
                exit 1
              fi

              if [ -z "$storage_token" ] || [ -z "$backup_token" ] || [ -z "$indicator_token" ]; then
                printf '%s\n' 'ntfy env prompt must define NTFY_AUTH_TOKENS for storage-publisher:storage-alerts, backup-publisher:backup-alerts and indicator-publisher:indicator-alerts' >&2
                exit 1
              fi

              # Always normalize ACCESS so older prompts (write-only topics) become
              # subscribe-capable without requiring a manual re-prompt.
              # Deterministic: strip any existing NTFY_AUTH_ACCESS lines and
              # append exactly one canonical line (idempotent across regenerations).
              grep -v '^NTFY_AUTH_ACCESS=' "$out/env" > "$out/env.tmp"
              mv "$out/env.tmp" "$out/env"
              printf '%s\n' "NTFY_AUTH_ACCESS=$canonical_access" >> "$out/env"
            else
              token_suffix=$(head -c 32 /dev/urandom | od -An -tx1 -v | tr -d ' \n' | cut -c1-29)
              storage_token="tk_$token_suffix"
              backup_token="tk_$(head -c 32 /dev/urandom | od -An -tx1 -v | tr -d ' \n' | cut -c1-29)"
              indicator_token="tk_$(head -c 32 /dev/urandom | od -An -tx1 -v | tr -d ' \n' | cut -c1-29)"

              cat > "$out/env" <<EOF
      NTFY_AUTH_FILE=/var/lib/ntfy-sh/user.db
      NTFY_AUTH_DEFAULT_ACCESS=deny-all
      NTFY_AUTH_USERS=storage-publisher:$fallback_storage_hash:user,backup-publisher:$fallback_backup_hash:user,indicator-publisher:$fallback_indicator_hash:user
      NTFY_AUTH_ACCESS=$canonical_access
      NTFY_AUTH_TOKENS=storage-publisher:$storage_token:storage-alerts,backup-publisher:$backup_token:backup-alerts,indicator-publisher:$indicator_token:indicator-alerts
      EOF
            fi

            printf '%s\n' "$storage_token" > "$out/storage-token"
            printf '%s\n' "$backup_token" > "$out/backup-token"
            printf '%s\n' "$indicator_token" > "$out/indicator-token"
    '';
    meta.tags = ["service" "ntfy"];
  };
}
