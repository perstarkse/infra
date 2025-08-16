{
  "api-key-cloudflare-dns" = {
    share = true;
    files = {
      api-token = {
        mode = "0400";
        neededFor = "users";
        group = "users";
      };
    };
    prompts = {
      api-token = {
        description = "Cloudflare API token";
        persist = true;
        type = "hidden";
      };
    };
    script = ''
        cp "$prompts/api-token" "$out/api-token"
    '';
    meta = {
      tags = [ "cloudflare" "api-key" "dns" ];
    };
  };
} 