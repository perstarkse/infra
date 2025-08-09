{
  "ddclient" = {
    files = {
      "ddclient.conf" = {
        mode = "0400";
      };
    };
    prompts = {
      "ddclient.conf" = {
        description = "ddclient configuration file contents";
        persist = true;
        type = "hidden";
      };
    };
    script = ''
      cp "$prompts/ddclient.conf" "$out/ddclient.conf"
    '';
    meta = {
      tags = [ "ddclient" "service" ];
    };
  };
} 