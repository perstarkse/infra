{
  config.flake.homeModules.rbw = {
    pkgs,
    config,
    lib,
    ...
  }: {
    options.my.programs.rbw.pinentrySource = lib.mkOption {
      type = lib.types.enum ["auto" "gui" "tty"];
      default = "auto";
      description = "Determines which pinentry to use for RBW.";
    };

    config = {
      programs.rbw = {
        enable = true;
        settings = {
          base_url = "https://vault.stark.pub";
          email = "per@starks.cloud";
          pinentry = lib.mkIf config.programs.rbw.enable (
            let
              isGraphicalSession = (pkgs ? wayland) || (pkgs ? xorg);
            in
              if config.my.programs.rbw.pinentrySource == "tty"
              then pkgs.pinentry-curses
              else if config.my.programs.rbw.pinentrySource == "gui"
              then pkgs.pinentry-qt
              else # auto
                if isGraphicalSession
                then pkgs.pinentry-qt
                else pkgs.pinentry-curses
          );
        };
      };
    };
  };
}
