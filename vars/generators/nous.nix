{
  "nous" = {
    share = true;
    files = {
      env = {
        mode = "0400";
        neededFor = "users";
      };
    };
    prompts = {
      env = {
        description = "Nous environment file content (KEY=VALUE)";
        persist = true;
        type = "hidden";
      };
    };
    script = ''
      # Robust prompts handling
      _prompts_dir="''${prompts:-}"
      if [ -z "$_prompts_dir" ] || [ ! -d "$_prompts_dir" ]; then
         _prompts_dir=""
      fi

      if [ -n "$_prompts_dir" ] && [ -s "$_prompts_dir/env" ]; then
        cp "$_prompts_dir/env" "$out/env"
      else
        # Auto-generate placeholder
        echo "# Auto-generated placeholder for Nous" > "$out/env"
        secret=$(head -c 32 /dev/urandom | base64 -w0)
        echo "NOUS_SECRET_KEY=$secret" >> "$out/env"
      fi
    '';
    meta.tags = ["service" "nous"];
  };
}
