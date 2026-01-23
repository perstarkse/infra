{
  "ddclient" = {
    share = true;
    files = {
      "ddclient.conf" = {
        mode = "0400";
      };
    };
    prompts = {
      "ddclient.conf" = {
        description = "Cloudflare API token for stark.pub zone (ddclient)";
        persist = true;
        type = "hidden";
      };
    };
    script = ''
      cp "$prompts/ddclient.conf" "$out/ddclient.conf"
    '';
    meta = {
      tags = ["ddclient" "service"];
    };
  };
}
