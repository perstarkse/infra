{inputs, ...}: {
  config.flake.homeModules.sway = {
    pkgs,
    lib,
    osConfig,
    ...
  }: {
    home.packages = with pkgs; [
      wofi
      grim
      slurp
      wl-clipboard
      dunst
    ];

    stylix.targets.sway.enable = true;

    wayland.windowManager.sway = {
      enable = true;
      extraOptions = ["--unsupported-gpu"];

      config = let
        mod = "Mod4";
        terminal = osConfig.my.gui._terminalCommand;
      in {
        modifier = mod;
        inherit terminal;

        workspaceAutoBackAndForth = true;
        defaultWorkspace = "workspace number 1";

        gaps = {
          inner = 0;
          outer = 0;
        };

        bars = [];

        startup = [
          {command = "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP";}
          {
            command = "${inputs.sway-focus-flash.packages.${pkgs.system}.sway-focus-flash}/bin/sway-focus-flash --start-opacity 0.85";
            always = true;
          }
        ];

        output = {
          "DP-1" = {
            resolution = "3440x1440@144Hz";
            scale = "1.0";
            adaptive_sync = "on";
          };
        };

        input = {
          "type:keyboard" = {
            xkb_layout = "us,se";
            xkb_options = "grp:alt_shift_toggle";
          };
          "type:pointer" = {
            accel_profile = "flat";
            pointer_accel = "0";
          };
        };

        keybindings = lib.mkOptionDefault {
          "${mod}+Return" = "exec ${terminal}";
          "${mod}+d" = "exec ${pkgs.wofi}/bin/wofi --show drun";
          "${mod}+a" = "exec, rofi-rbw";
          "${mod}+Shift+q" = "kill";
          "${mod}+z" = "exec ${pkgs.grim}/bin/grim -g \"$(${pkgs.slurp}/bin/slurp)\" - | ${pkgs.wl-clipboard}/bin/wl-copy -t image/png";
          "${mod}+Shift+z" = "exec ${pkgs.grim}/bin/grim - | ${pkgs.wl-clipboard}/bin/wl-copy -t image/png";
          "${mod}+Print" = "exec blinkstick-scripts white";
          "${mod}+Shift+Print" = "exec blinkstick-scripts off";
          "${mod}+Control+l" = "exec systemctl suspend";
          "${mod}+h" = "focus left";
          "${mod}+j" = "focus down";
          "${mod}+k" = "focus up";
          "${mod}+l" = "focus right";
          "${mod}+Shift+h" = "move left";
          "${mod}+Shift+j" = "move down";
          "${mod}+Shift+k" = "move up";
          "${mod}+Shift+l" = "move right";
          "${mod}+b" = "split h";
          "${mod}+v" = "split v";
          "${mod}+f" = "fullscreen toggle";
          "${mod}+Shift+s" = "floating toggle";
          "${mod}+1" = "workspace number 1";
          "${mod}+2" = "workspace number 2";
          "${mod}+3" = "workspace number 3";
          "${mod}+4" = "workspace number 4";
          "${mod}+5" = "workspace number 5";
          "${mod}+6" = "workspace number 6";
          "${mod}+7" = "workspace number 7";
          "${mod}+8" = "workspace number 8";
          "${mod}+9" = "workspace number 9";
          "${mod}+0" = "workspace number 10";
          "${mod}+Shift+1" = "move container to workspace number 1";
          "${mod}+Shift+2" = "move container to workspace number 2";
          "${mod}+Shift+3" = "move container to workspace number 3";
          "${mod}+Shift+4" = "move container to workspace number 4";
          "${mod}+Shift+5" = "move container to workspace number 5";
          "${mod}+Shift+6" = "move container to workspace number 6";
          "${mod}+Shift+7" = "move container to workspace number 7";
          "${mod}+Shift+8" = "move container to workspace number 8";
          "${mod}+Shift+9" = "move container to workspace number 9";
          "${mod}+Shift+0" = "move container to workspace number 10";
          "${mod}+r" = "mode resize";
        };

        modes = {
          resize = {
            "h" = "resize shrink width 30 px or 3 ppt";
            "j" = "resize grow height 30 px or 3 ppt";
            "k" = "resize shrink height 30 px or 3 ppt";
            "l" = "resize grow width 30 px or 3 ppt";
            "Return" = "mode default";
            "Escape" = "mode default";
          };
        };

        floating.modifier = mod;
      };

      extraConfig = ''
        default_border pixel 1
      '';
    };
  };
}
