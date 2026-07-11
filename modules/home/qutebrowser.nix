{
  config.flake.homeModules.qutebrowser = {
    pkgs,
    lib,
    config,
    osConfig,
    ...
  }: let
    cfg = config.my.qutebrowser;
    inherit (cfg) enableTor;
  in {
    options.my.qutebrowser = {
      enable = lib.mkEnableOption "qutebrowser";
      enableTor = lib.mkEnableOption "route qutebrowser through a local Tor SOCKS proxy";
    };

    config = lib.mkIf cfg.enable {
      programs.qutebrowser = {
        enable = true;
        keyBindings = {
          normal = {
            "P" = "hint links spawn ${pkgs.mpv}/bin/mpv {hint-url}";
            "j" = "scroll-px 0 700";
            "k" = "scroll-px 0 -700";
            ",c" = "spawn sh -c '${pkgs.w3m}/bin/w3m -dump \"{url}\" | ${pkgs.wl-clipboard}/bin/wl-copy'";
          };
        };
        searchEngines = {
          DEFAULT = "https://duckduckgo.com/?q={}";
          sx = "https://search.lan.stark.pub/search?q={}";
          ddg = "https://duckduckgo.com/?q={}";
          nw = "https://nixos.wiki/index.php?search={}&go=Go";
          mn = "https://mynixos.com/search?q={}";
        };
        settings =
          {
            # url.start_pages = "https://search.lan.stark.pub";
            editor.command = [osConfig.my.gui._terminalCommand "hx" "{file}"];
            content = {
              javascript.clipboard = "access-paste";
              pdfjs = !enableTor;
              javascript.enabled = !enableTor;
            };
          }
          // lib.optionalAttrs enableTor {
            settings.content.proxy = "socks://localhost:9050";
          };
      };

      home.packages = with pkgs; [mpv w3m];
    };
  };
}
