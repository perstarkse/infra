{
  "garage" = {
    share = true;
    files = {
      rpc_secret = {
        mode = "0400";
        neededFor = "users";
      };
    };
    prompts = {
      rpc_secret = {
        description = "Garage RPC secret (hex encoded 32 bytes)";
        persist = true;
        type = "hidden";
      };
    };
    script = ''
      _prompts_dir="''${prompts:-}"
      if [ -z "$_prompts_dir" ] || [ ! -d "$_prompts_dir" ]; then
         _prompts_dir=""
      fi

      if [ -n "$_prompts_dir" ] && [ -s "$_prompts_dir/rpc_secret" ]; then
        cp "$_prompts_dir/rpc_secret" "$out/rpc_secret"
      else
        # Auto-generate random hex secret (32 bytes = 64 hex chars)
        head -c 32 /dev/urandom | od -v -An -tx1 | tr -d ' \n' > "$out/rpc_secret"
      fi
    '';
    meta.tags = ["service" "garage" "makemake" "io"];
  };
}
