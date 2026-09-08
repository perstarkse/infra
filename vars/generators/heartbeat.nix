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

            # Gatus API token, distinct from the WAN push bearer (see
            # my.heartbeat.receiver.gatusApiTokenEnvVar). Appended on
            # regeneration when missing so existing provisions heal without
            # manual rotation; never overwrites a provisioned value.
            if ! grep -q '^HEARTBEAT_GATUS_TOKEN=' "$out/env"; then
              printf 'HEARTBEAT_GATUS_TOKEN=%s\n' "$(head -c 32 /dev/urandom | od -v -An -tx1 | tr -d ' \n')" >> "$out/env"
            fi
    '';
    meta.tags = ["service" "heartbeat"];
  };
}
