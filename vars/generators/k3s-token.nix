{
  "k3s" = {
    share = true;
    files = {
      token = {
        mode = "0400";
        neededFor = "users";
      };
    };
    prompts = {
      token = {
        description = "k3s token";
        persist = true;
        type = "hidden";
      };
    };
    script = ''
      cp "$prompts/token" "$out/token"
    '';
    meta = {
      tags = [ "k3s" ];
    };
  };
} 