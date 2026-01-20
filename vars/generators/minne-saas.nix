{
  "minne-saas" = {
    share = true;
    files = {
      env = {
        mode = "0400";
        neededFor = "users";
      };
    };
    prompts = {
      env = {
        description = "Content of the Minne SaaS environment file";
        persist = true;
        type = "hidden";
      };
    };
    script = ''
      cp "$prompts/env" "$out/env"
    '';
    meta = {
      tags = ["minne-saas"];
      # tags = ["makemake" "service" "minne-saas"];
    };
  };
}
