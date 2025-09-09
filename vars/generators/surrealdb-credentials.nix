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
      cp "$prompts/credentials" "$out/credentials"
    '';
    meta = {
      tags = ["oumuamua" "service" "surrealdb"];
    };
  };
}
