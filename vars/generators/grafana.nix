{
  "grafana" = {
    share = true;
    files = {
      secret_key = {
        mode = "0400";
        neededFor = "users";
      };
    };
    prompts = {
      secret_key = {
        description = "Grafana session/cookie signing key (passed via $__file provider, never baked into the store)";
        persist = true;
        type = "hidden";
      };
    };
    script = ''
      _prompts_dir="''${prompts:-}"
      if [ -z "$_prompts_dir" ] || [ ! -d "$_prompts_dir" ]; then
         _prompts_dir=""
      fi

      if [ -n "$_prompts_dir" ] && [ -s "$_prompts_dir/secret_key" ]; then
        cp "$_prompts_dir/secret_key" "$out/secret_key"
      else
        # Auto-generate random signing key (32 bytes hex)
        head -c 32 /dev/urandom | od -v -An -tx1 | tr -d ' \n' > "$out/secret_key"
      fi
    '';
    meta.tags = ["service" "grafana" "io"];
  };
}
