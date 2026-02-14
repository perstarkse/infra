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
        description = "Wake proxy env file (WOL_PROXY_PASSWORD_HASH=... and WOL_PROXY_SESSION_SECRET=...)";
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
        session_secret=$(head -c 32 /dev/urandom | base64 -w0)
        cat > "$out/env" <<EOF
# Auto-generated template for wake-proxy.
# Replace WOL_PROXY_PASSWORD_HASH with a real Argon2 hash before deploy.
WOL_PROXY_PASSWORD_HASH=REPLACE_WITH_ARGON2_HASH
WOL_PROXY_SESSION_SECRET=$session_secret
EOF
      fi
    '';
    meta.tags = ["service" "wake-proxy"];
  };
}
