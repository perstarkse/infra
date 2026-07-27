_: {
  "accounted-mcp-key" = {
    share = true;
    files = {
      env = {
        mode = "0400";
        neededFor = "users";
      };
    };
    prompts = {
      api_key = {
        description = "Accounted MCP API key (gnubok_sk_live_* from https://accounting.lan.stark.pub/settings/api)";
        persist = true;
        type = "hidden";
      };
    };
    script = ''
      _prompts_dir="''${prompts:-}"
      if [ -z "$_prompts_dir" ] || [ ! -d "$_prompts_dir" ]; then
        echo "ACCOUNTED_MCP_API_KEY=placeholder-set-me" > "$out/env"
        exit 0
      fi
      printf 'ACCOUNTED_MCP_API_KEY=%s\n' "$(cat "$_prompts_dir/api_key")" > "$out/env"
    '';
    meta.tags = ["accounted-mcp" "charon"];
  };
}
