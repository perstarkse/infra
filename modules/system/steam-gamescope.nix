{
  config.flake.nixosModules.steam-gamescope = {
    config,
    pkgs,
    lib,
    ...
  }: let
    cfg = config.my.steamGamescope;
  in {
    options.my.steamGamescope = {
      enable = lib.mkEnableOption "Steam in a gamescope session";

      width = lib.mkOption {
        type = lib.types.int;
        default = 1920;
        description = "Internal gamescope width.";
      };

      height = lib.mkOption {
        type = lib.types.int;
        default = 1080;
        description = "Internal gamescope height.";
      };

      refreshRate = lib.mkOption {
        type = lib.types.int;
        default = 60;
        description = "Internal gamescope refresh rate.";
      };
    };

    config = lib.mkIf cfg.enable {
      hardware.opengl.driSupport32Bit = true;
      services.pipewire.alsa.support32Bit = true;

      programs = {
        # Correct override: only use real pkgs attributes here
        steam = {
          package = pkgs.steam.override {
            extraLibraries = pkgs:
              with pkgs; [
                systemd # pulls in libsystemd/libudev, multiarch
                nssmdns # mDNS NSS plugin, multiarch
                # add more *real* packages here if you confirm they are missing
                # curlWithGnuTls   # already in Steam fhsenv by default
                # dbus             # already pulled via dbus-glib in fhsenv
              ];
            # no extraPkgs needed for now
          };
          enable = true;
          remotePlay.openFirewall = true;

          gamescopeSession = {
            enable = true;

            args = [
              "-W"
              (toString cfg.width)
              "-H"
              (toString cfg.height)
              "-w"
              (toString cfg.width)
              "-h"
              (toString cfg.height)
              "-r"
              (toString cfg.refreshRate)
              "-f"
              "-e"
            ];

            steamArgs = [
              "-pipewire-dmabuf"
              "-gamepadui"
            ];

            env = {
              XDG_RUNTIME_DIR = "/run/user/$UID";
              DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/$UID/bus";
            };
          };
        };

        gamescope = {
          enable = true;
          capSysNice = true;
        };
      };
    };
  };
}
