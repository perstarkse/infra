{
  config.flake.homeModules.xdg-mimeapps = {
    pkgs,
    osConfig,
    ...
  }: {
    xdg = {
      mimeApps = {
        enable = true;
        defaultApplications = {
          "text/plain" = ["helix.desktop"];
          "text/markdown" = ["helix.desktop"];
          "application/pdf" = ["mupdf.desktop"];
          "inode/directory" = ["ranger.desktop"];

          "x-scheme-handler/http" = ["qutebrowser.desktop"];
          "x-scheme-handler/https" = ["qutebrowser.desktop"];

          "text/*" = ["helix.desktop"];
        };
      };
      desktopEntries = {
        # Define the .desktop file for Helix
        helix = {
          name = "Helix Editor";
          # %U can handle multiple files/URLs
          exec = "${pkgs.helix}/bin/hx %U";
          # Helix is a Terminal User Interface (TUI) application
          terminal = true;
          mimeType = ["text/plain" "text/markdown"];
        };

        # Define the .desktop file for Ranger (launched in Terminal)
        ranger = {
          name = "Ranger File Manager";
          # Launch terminal, and tell it to execute ranger
          exec = "${osConfig.my.gui._terminalCommand} -e ${pkgs.ranger}/bin/ranger %U";
          # Terminal provides the terminal, so this entry itself doesn't need one
          terminal = false;
          mimeType = ["inode/directory"];
        };

        mupdf = {
          name = "MuPDF";
          exec = "${pkgs.mupdf}/bin/mupdf %f";
          mimeType = ["application/pdf"];
          startupNotify = true;
          terminal = false;
        };
      };
    };
  };
}
