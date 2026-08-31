_: {
  config.flake.homeModules.tether = {
    lib,
    config,
    pkgs,
    ...
  }: let
    cfg = config.my.tether;
  in {
    options.my.tether = {
      enable = lib.mkEnableOption "Tether iPhone-bridge (GTK app + user daemon)";

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.callPackage ../../pkgs/tether {};
        defaultText = lib.literalExpression "pkgs.callPackage ../../pkgs/tether {}";
        description = "The tether package providing tetherd/tether/tether-gtk/tether-dialog.";
      };

      nativeMessaging = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Register the tether native-messaging host with Firefox, Thunderbird,
          and Chromium for the browser/mail OTP extensions.
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      home.packages = [cfg.package];

      # tetherd manages clipboard/files/messages for this desktop session; it
      # needs WAYLAND_DISPLAY (imported by niri-session) and the user D-Bus.
      systemd.user.services.tetherd = {
        Unit = {
          Description = "Tether iPhone bridge daemon";
          # BindsTo stops tetherd with the session AND prevents Restart from
          # crash-looping it after the compositor (and its Wayland socket) is
          # gone at logout — PartOf alone stops it but on-failure Restart can
          # still race teardown.
          BindsTo = ["graphical-session.target"];
          PartOf = ["graphical-session.target"];
          After = ["graphical-session.target"];
        };
        Service = {
          Type = "simple";
          ExecStart = "${cfg.package}/bin/tetherd";
          Restart = "on-failure";
          RestartSec = 5;
          # btmgmt is popen()'d for Bluetooth diagnostics (objects.cpp) and
          # tether-dialog is spawned via PATH fallback; prepend, don't clobber
          # the session PATH that the graphical session provides.
          Environment = ["PATH=${pkgs.bluez}/bin:/run/current-system/sw/bin"];
        };
        Install.WantedBy = ["graphical-session.target"];
      };

      # NMH manifest path field is an absolute store path to
      # $out/bin/tether-native-host, so the plain package works for all three.
      # On Linux, HM merges firefox+thunderbird NMH into one shared
      # ~/.mozilla/native-messaging-hosts, so register each only when the
      # corresponding program is actually enabled (avoids creating the dir on
      # hosts with neither browser nor mail client).
      programs = {
        firefox.nativeMessagingHosts = lib.optionals (cfg.nativeMessaging && config.programs.firefox.enable) [cfg.package];
        thunderbird.nativeMessagingHosts = lib.optionals (cfg.nativeMessaging && config.programs.thunderbird.enable) [cfg.package];
        chromium.nativeMessagingHosts = lib.optionals (cfg.nativeMessaging && config.programs.chromium.enable) [cfg.package];
      };
    };
  };
}
