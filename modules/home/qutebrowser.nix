{
  config.flake.homeModules.qutebrowser = {pkgs, ...}: {
    programs.qutebrowser = {
      enable = true;
      keyBindings = {
        normal = {
          "P" = "hint links spawn ${pkgs.mpv}/bin/mpv {hint-url}";
          "j" = "scroll-px 0 700";
          "k" = "scroll-px 0 -700";
        };
      };
      settings = {
        editor.command = ["kitty" "hx" "{file}"];
        content.javascript.clipboard = "access-paste";
        content.pdfjs = true;
      };
      # extraConfig = ''
      #   [aliases]
      #   w3m_dump = "w3m -dump {url} | wl-copy"

      #   [commands]
      #   spawn --userscript w3m_dump
      # '';
    };
  };
}
