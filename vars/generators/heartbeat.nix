{
  "heartbeat" = {
    share = true;
    files = {
      env = {
        mode = "0400";
        neededFor = "users";
      };
    };
    prompts = {
      env = {
        description = "heartbeat env (push token + target URL)";
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
              cat > "$out/env" <<'EOF'
      HEARTBEAT_PUSH_TOKEN=change-me
      HEARTBEAT_URL=http://change-me-zerotier-address:18080/heartbeat
      EOF
            fi
    '';
    meta.tags = ["service" "heartbeat"];
  };
}
