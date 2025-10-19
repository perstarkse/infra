{
  config.flake.homeModules.niri = {
    pkgs,
    lib,
    osConfig,
    ...
  }: let
    guiCfg = osConfig.my.gui;
    # wallpaper = ../../wallpaper.jpg;
  in {
    config = lib.mkIf (guiCfg.enable && guiCfg.session == "niri") {
      home.packages = with pkgs; [
        wofi
        grim
        slurp
        wl-clipboard
        dunst
      ];

      # stylix.targets.niri.enable = lib.mkDefault true;

      xdg.configFile."niri/config.kdl".source = ./niri-config.kdl;

      # systemd.user.services.swaybg = {
      #   Unit = {
      #     Description = "Set wallpaper via swaybg for the Niri session";
      #     PartOf = ["graphical-session.target"];
      #     After = ["graphical-session.target"];
      #   };
      #   Install = {
      #     WantedBy = ["graphical-session.target"];
      #   };
      #   Service = {
      #     ExecStart = "${pkgs.swaybg}/bin/swaybg -i ${wallpaper} -m fill";
      #     Restart = "on-failure";
      #   };
      # };
    };
    #   imports = [
    #     inputs.niri.homeModules.config
    #     inputs.niri.homeModules.stylix
    #   ];

    #   options.programs.niri.enable = lib.mkEnableOption "the niri compositor (home-manager)";

    #   config = lib.mkIf (osConfig.my.gui.enable && osConfig.my.gui.session == "niri") {
    #     home.packages = with pkgs; [
    #       wofi
    #       grim
    #       slurp
    #       wl-clipboard
    #       dunst
    #     ];

    #     stylix.targets.niri.enable = lib.mkDefault true;

    #     programs.niri = {
    #       enable = lib.mkDefault true;
    #       settings = {
    #         input = {
    #           mod-key = mod;
    #           keyboard = {
    #             xkb.layout = "us,se";
    #             xkb.options = "grp:alt_shift_toggle";
    #           };
    #           mouse.accel-profile = "flat";
    #           mouse.accel-speed = 0.0;
    #         };

    #         outputs."DP-1" = {
    #           mode = {
    #             width = 3440;
    #             height = 1440;
    #             refresh = 144.0;
    #           };
    #           scale = 1.0;
    #           variable-refresh-rate = true;
    #           focus-at-startup = true;
    #         };

    #         layout = {
    #           gaps = 0;
    #         };

    #         environment = {
    #           NIXOS_OZONE_WL = "1";
    #         };

    #         binds = with actions; {
    #           "${mod}+Return".action = spawn terminal;
    #           "XF86AudioRaiseVolume".action = spawn wpctl "set-volume" "@DEFAULT_AUDIO_SINK@" "5%+";
    #           "XF86AudioLowerVolume".action = spawn wpctl "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-";
    #           "XF86AudioMute".action = spawn wpctl "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle";
    #           "${mod}+d".action = spawn "wofi" "--show" "drun";
    #           "${mod}+a".action = spawn "rofi-rbw";
    #           "${mod}+Shift+q".action = close-window;
    #           "${mod}+z".action = sh ''
    #             ${grimExe} -g "$(${slurpExe})" - | ${wlCopy} -t image/png
    #           '';
    #           "${mod}+Shift+z".action = sh ''
    #             ${grimExe} - | ${wlCopy} -t image/png
    #           '';
    #           "${mod}+Print".action = spawn "blinkstick-scripts" "white";
    #           "${mod}+Shift+Print".action = spawn "blinkstick-scripts" "off";
    #           "${mod}+Control+l".action = spawn "systemctl" "suspend";
    #           "${mod}+h".action = focus-column-left;
    #           "${mod}+j".action = focus-window-down;
    #           "${mod}+k".action = focus-window-up;
    #           "${mod}+l".action = focus-column-right;
    #           "${mod}+Shift+h".action = move-column-left;
    #           "${mod}+Shift+j".action = move-window-down;
    #           "${mod}+Shift+k".action = move-window-up;
    #           "${mod}+Shift+l".action = move-column-right;
    #           "${mod}+f".action = toggle-windowed-fullscreen;
    #           "${mod}+Shift+s".action = toggle-window-floating;
    #           "${mod}+1".action = focus-workspace 1;
    #           "${mod}+2".action = focus-workspace 2;
    #           "${mod}+3".action = focus-workspace 3;
    #           "${mod}+4".action = focus-workspace 4;
    #           "${mod}+5".action = focus-workspace 5;
    #           "${mod}+6".action = focus-workspace 6;
    #           "${mod}+7".action = focus-workspace 7;
    #           "${mod}+8".action = focus-workspace 8;
    #           "${mod}+9".action = focus-workspace 9;
    #           "${mod}+0".action = focus-workspace 10;
    #           "${mod}+Shift+1".action = move-window-to-workspace 1;
    #           "${mod}+Shift+2".action = move-window-to-workspace 2;
    #           "${mod}+Shift+3".action = move-window-to-workspace 3;
    #           "${mod}+Shift+4".action = move-window-to-workspace 4;
    #           "${mod}+Shift+5".action = move-window-to-workspace 5;
    #           "${mod}+Shift+6".action = move-window-to-workspace 6;
    #           "${mod}+Shift+7".action = move-window-to-workspace 7;
    #           "${mod}+Shift+8".action = move-window-to-workspace 8;
    #           "${mod}+Shift+9".action = move-window-to-workspace 9;
    #           "${mod}+Shift+0".action = move-window-to-workspace 10;
    #         };
    #       };
    #     };
    #   };
    # };
  };
}
