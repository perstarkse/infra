_: {
  "digikey" = {
    share = true;
    files = {
      env = {
        mode = "0400";
        neededFor = "users";
      };
    };
    prompts = {
      client_id = {
        description = "DigiKey API client ID (https://developer.digikey.com/my-digikey/applications)";
        persist = true;
        type = "hidden";
      };
      client_secret = {
        description = "DigiKey API client secret";
        persist = true;
        type = "hidden";
      };
    };
    script = ''
      _prompts_dir="''${prompts:-}"
      if [ -z "$_prompts_dir" ] || [ ! -d "$_prompts_dir" ]; then
        echo "DIGIKEY_CLIENT_ID=placeholder-set-me" > "$out/env"
        echo "DIGIKEY_CLIENT_SECRET=placeholder-set-me" >> "$out/env"
        exit 0
      fi
      printf 'DIGIKEY_CLIENT_ID=%s\n' "$(cat "$_prompts_dir/client_id")" > "$out/env"
      printf 'DIGIKEY_CLIENT_SECRET=%s\n' "$(cat "$_prompts_dir/client_secret")" >> "$out/env"
    '';
    meta.tags = ["digikey" "charon"];
  };
}
