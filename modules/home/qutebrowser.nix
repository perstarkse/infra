{config, ...}: let
  enableTor = config.my.programs.qutebrowser.enableTor or false;
in {
  config.flake.homeModules.qutebrowser = {
    pkgs,
    lib,
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
      settings =
        {
          editor.command = ["kitty" "hx" "{file}"];
          content.javascript.clipboard = "access-paste";
          content.pdfjs = !enableTor;
          content.javascript.enabled = !enableTor;
        }
        // lib.optionalAttrs enableTor {
          settings.content.proxy = "socks://localhost:9050";
        };
    };

    home.packages = with pkgs; [mpv w3m];
  };
}
