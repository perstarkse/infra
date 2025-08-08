{
  "minne-env" = {
    files = {
      env = {
        # description = "Environment file for Minne service";
        mode = "0400";
        neededFor = "users";
      };
    };
    prompts = {
      env = {
        description = "Content of the Minne environment file";
        persist = true;
        # display.label = "Minne env";
        type = "hidden";
      };
    };
    script = ''
      cp "$prompts/env" "$out/env"
    '';
    meta = {
      tags = [ "oumuamua" "service" "minne" ];
    };
  };
} 