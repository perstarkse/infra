{
  "surrealdb-credentials" = {
    files = {
      credentials = {
        # description = "Environment file for SurrealDB credentials (e.g., SURREALDB_USER=..., SURREALDB_PASS=...)";
        mode = "0400";
        neededFor = "users";
      };
    };
    prompts = {
      credentials = {
        description = "Content of the SurrealDB credentials environment file";
        persist = true;
        # display.label = "SurrealDB credentials env";
        type = "hidden";
      };
    };
    script = ''
      cp "$prompts/credentials" "$out/credentials"
    '';
    meta = {
      tags = [ "oumuamua" "service" "surrealdb" ];
    };
  };
}
