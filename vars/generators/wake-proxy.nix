{
  "wake-proxy" = {
    share = true;
    files = {
      env = {
        mode = "0400";
        neededFor = "users";
      };
    };
    prompts = {
      env = {
        description = "Wake proxy env file (WAKEPROXY_PASSWORD_HASH=... and WAKEPROXY_SESSION_SECRET=...)";
        persist = true;
        type = "hidden";
      };
    };
    script = ''
      _prompts_dir="''${prompts:-}"
      if [ -z "$_prompts_dir" ] || [ ! -d "$_prompts_dir" ]; then
        _prompts_dir=""
      fi

      if [ -n "$_prompts_dir" ] && [ -s "$_prompts_dir/env" ]; then
        cp "$_prompts_dir/env" "$out/env"
      else
        echo "wake-proxy secret generation requires a provided env file prompt" >&2
        echo "expected WAKEPROXY_PASSWORD_HASH and WAKEPROXY_SESSION_SECRET" >&2
        exit 1
      fi

      if ! grep -q '^WAKEPROXY_PASSWORD_HASH=' "$out/env"; then
        echo "wake-proxy env is missing WAKEPROXY_PASSWORD_HASH" >&2
        exit 1
      fi

      if ! grep -q '^WAKEPROXY_SESSION_SECRET=' "$out/env"; then
        echo "wake-proxy env is missing WAKEPROXY_SESSION_SECRET" >&2
        exit 1
      fi

      if grep -q '^WAKEPROXY_PASSWORD_HASH=REPLACE_WITH_ARGON2_HASH$' "$out/env"; then
        echo "wake-proxy env still contains placeholder WAKEPROXY_PASSWORD_HASH" >&2
        exit 1
      fi
    '';
    meta.tags = ["service" "wake-proxy"];
  };
}
