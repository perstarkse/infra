{config, ...}: let
  enableTor = config.my.programs.qutebrowser.enableTor or false;
in {
  config.flake.homeModules.qutebrowser = {
    pkgs,
    lib,
    osConfig,
    ...
  }: {
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
        DEFAULT = "https://search.lan.stark.pub/search?q={}";
        sx = "https://search.lan.stark.pub/search?q={}";
        ddg = "https://duckduckgo.com/?q={}";
        nw = "https://nixos.wiki/index.php?search={}&go=Go";
        mn = "https://mynixos.com/search?q={}";
      };
      settings =
        {
          url.start_pages = "https://search.lan.stark.pub";
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
}
