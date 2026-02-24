{
  "gatus" = {
    share = true;
    files = {
      env = {
        mode = "0400";
        neededFor = "users";
      };
    };
    prompts = {
      env = {
        description = "Gatus env file (SMTP + recipient list)";
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
      GATUS_SMTP_HOST=mail-eu.smtp2go.com
      GATUS_SMTP_FROM=services@stark.pub
      GATUS_SMTP_USERNAME=change-me
      GATUS_SMTP_PASSWORD=change-me
      GATUS_ALERT_EMAIL_TO=you@example.com,other@example.com
      HEARTBEAT_GATUS_TOKEN=change-me
      EOF
            fi
    '';
    meta.tags = ["service" "gatus"];
  };
}
