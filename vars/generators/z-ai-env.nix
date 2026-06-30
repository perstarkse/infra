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
        persist = true;
        type = "multiline-hidden";
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
