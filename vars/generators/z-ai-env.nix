{
  "z-ai-env" = {
    share = true;
    files = {
      env = {
        mode = "0400";
        neededFor = "users";
      };
    };
    prompts = {
      env = {
        description = "A set of environment variables needed to work with z.ai LLMs";
        multiline = true;
        persist = true;
        type = "hidden";
      };
    };
    script = ''
      cp "$prompts/env" "$out/env"
    '';
    meta = {
      tags = ["charon" "development"];
    };
  };
}
