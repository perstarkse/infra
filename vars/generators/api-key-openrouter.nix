{
  "api-key-openrouter" = {
    share = true;
    files = {
      api_key = {
        mode = "0400";
        neededFor = "users";
      };
    };
    prompts = {
      api_key = {
        description = "OpenRouter API key";
        persist = true;
        type = "hidden";
      };
    };
    script = ''
      cp "$prompts/api_key" "$out/api_key"
    '';
    meta = {
      tags = [ "openrouter" "api-key" "dev" "fish" ];
    };
  };
} 