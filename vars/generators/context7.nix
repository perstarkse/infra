{
  "context7" = {
    share = true;
    files = {
      env = {
        mode = "0400";
        neededFor = "users";
      };
    };
    prompts = {
      api_key = {
        description = "Context7 API key (from https://context7.com/dashboard)";
        persist = true;
        type = "hidden";
      };
    };
    script = ''
      _prompts_dir="''${prompts:-}"
      if [ -z "$_prompts_dir" ] || [ ! -d "$_prompts_dir" ]; then
        echo "CONTEXT7_API_KEY=placeholder-set-me" > "$out/env"
        exit 0
      fi
      printf 'CONTEXT7_API_KEY=%s\n' "$(cat "$_prompts_dir/api_key")" > "$out/env"
    '';
    meta = {
      tags = ["openchamber" "api-key" "dev"];
    };
  };
}
