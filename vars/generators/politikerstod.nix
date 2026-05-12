let
  mkPolitikerstodSecrets = name: {
    share = true;
    files = {
      env = {
        mode = "0400";
        neededFor = "users";
      };
    };
    prompts = {
      env = {
        description = "Politikerstöd (${name}) environment file content (OPENAI_API_KEY=..., JWT_SECRET=..., SMTP_PASSWORD=...)";
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
        echo "# Auto-generated secrets for Politikerstöd (${name})" > "$out/env"
        jwt=$(head -c 32 /dev/urandom | base64 -w0)
        echo "JWT_SECRET=$jwt" >> "$out/env"
        echo "OPENAI_API_KEY=sk-placeholder-change-me" >> "$out/env"
        echo "SMTP_USERNAME=user@example.com" >> "$out/env"
        echo "SMTP_PASSWORD=change-me" >> "$out/env"
      fi
    '';
    meta.tags = ["service" "politikerstod" "politikerstod-${name}"];
  };
in {
  "politikerstod" = mkPolitikerstodSecrets "default";
  "politikerstod-lekeberg" = mkPolitikerstodSecrets "lekeberg";
}
