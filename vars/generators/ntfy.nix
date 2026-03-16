{
  "ntfy" = {
    share = true;
    files = {
      env = {
        mode = "0400";
        neededFor = "services";
      };
      storage-token = {
        mode = "0400";
        neededFor = "services";
      };
    };
    prompts = {
      env = {
        description = "Optional ntfy env file (KEY=VALUE). If omitted, a minimal ntfy config with an auto-generated storage token is created.";
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

            storage_token=""
            has_storage_user=""
            fallback_storage_hash='$2b$05$eB0b8OHKgPgEHmrJsw5gB.HEneuR064tnHVgqTk94v/4.J6ruAwVe'

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
                          break
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
                          break
                          ;;
                      esac
                    done
                    ;;
                esac
              done < "$out/env"

              if [ -z "$has_storage_user" ]; then
                printf '%s\n' 'ntfy env prompt must define NTFY_AUTH_USERS for storage-publisher' >&2
                exit 1
              fi

              if [ -z "$storage_token" ]; then
                printf '%s\n' 'ntfy env prompt must define NTFY_AUTH_TOKENS for storage-publisher:storage-alerts' >&2
                exit 1
              fi
            else
              token_suffix=$(head -c 32 /dev/urandom | od -An -tx1 -v | tr -d ' \n' | cut -c1-29)
              storage_token="tk_$token_suffix"

              cat > "$out/env" <<EOF
      NTFY_AUTH_FILE=/var/lib/ntfy-sh/user.db
      NTFY_AUTH_DEFAULT_ACCESS=deny-all
      NTFY_AUTH_USERS=storage-publisher:$fallback_storage_hash:user
      NTFY_AUTH_ACCESS=storage-publisher:storage-alerts:wo
      NTFY_AUTH_TOKENS=storage-publisher:$storage_token:storage-alerts
      EOF
            fi

            printf '%s\n' "$storage_token" > "$out/storage-token"
    '';
    meta.tags = ["service" "ntfy"];
  };
}
