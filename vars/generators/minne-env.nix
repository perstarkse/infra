{
  "minne-env" = {
    share = true;
    files = {
      env = {
        mode = "0400";
        neededFor = "users";
      };
    };
    prompts = {
      env = {
        description = "Content of the Minne environment file";
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
        # Generate random secret using coreutils
        secret=$(head -c 32 /dev/urandom | base64 -w0)
        echo "MINNE_SECRET=$secret" > "$out/env"
      fi
    '';
    meta = {
      tags = ["oumuamua" "service" "minne"];
    };
  };
}
