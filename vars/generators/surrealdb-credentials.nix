{
  "surrealdb-credentials" = {
    share = true;
    files = {
      credentials = {
        mode = "0400";
        neededFor = "users";
      };
    };
    prompts = {
      credentials = {
        description = "Content of the SurrealDB credentials environment file";
        persist = true;
        type = "hidden";
      };
    };
    script = ''
      _prompts_dir="''${prompts:-}"
      if [ -z "$_prompts_dir" ] || [ ! -d "$_prompts_dir" ]; then
         _prompts_dir=""
      fi

      if [ -n "$_prompts_dir" ] && [ -s "$_prompts_dir/credentials" ]; then
        cp "$_prompts_dir/credentials" "$out/credentials"
      else
        user="root"
        pass=$(head -c 32 /dev/urandom | base64 -w0)
        echo "SURREALDB_USER=$user" > "$out/credentials"
        echo "SURREALDB_PASS=$pass" >> "$out/credentials"
      fi
    '';
    meta = {
      tags = ["makemake" "service" "surrealdb"];
    };
  };
}
