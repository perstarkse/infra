{inputs, ...}: {
  config.flake.homeModules.hyprland = {
    pkgs,
    lib,
    ...
  }: let
    mainMod = "SUPER";
  in {
    # 1. Integrate with theming and wallpaper
    stylix.targets.hyprland.enable = true;
    stylix.targets.hyprpaper.enable = true;

    programs.kitty.enable = true;

    home.packages = with pkgs; [
      # Ensure necessary packages are available
      kitty
      wofi
      grim
      slurp
      wl-clipboard
      rofi-emoji-wayland
    ];

    wayland.windowManager.hyprland = {
      enable = true;
      plugins = [
        inputs.hy3.packages.x86_64-linux.hy3
        inputs.hyprland-plugins.packages.${pkgs.system}.hyprfocus
      ];

      settings = {
        # --- Debug ---
        debug = {
          disable_logs = false;
        };

        # --- Window swallowing ---
        misc = {
          enable_swallow = true;
          swallow_regex = "^(kitty)^";
        };

        # --- Variables ---
        "$mainMod" = mainMod;

        # --- Animations ---
        animation = [
          "workspaces, 0"
          "windows, 0"
          "fade, 0"
        ];

        # --- Monitor Configuration ---
        monitor = [
          "DP-1, 3440x1440@143.85, 0x0, 1, vrr, 1"
        ];

        # --- Input ---
        input = {
          kb_layout = "us,se";
          kb_options = "grp:alt_shift_toggle";
          force_no_accel = true;
          sensitivity = 0;
          accel_profile = "flat";
        };

        # --- Plugins ---
        plugin = {
          nstack = {
            layout = {
              stacks = 3; # Three total columns
              mfact = 0; # All stacks are equal size
              new_is_master = 0; # New windows don't become master
            };
          };
          hyprfocus = {
            enabled = true;
            animate_floating = false;
            animate_workspacechange = false;
            focus_animation = "flash"; # flash, shrink, none

            bezier = [
              "bezIn, 0.5, 0.0, 1.0, 0.5"
              "bezOut, 0.0, 0.5, 0.5, 1.0"
              "overshot, 0.05, 0.9, 0.1, 1.05"
              "smoothOut, 0.36, 0, 0.66, -0.56"
              "smoothIn, 0.25, 1, 0.5, 1"
              "realsmooth, 0.28, 0.29, 0.69, 1.08"
              "easeInOutBack, 0.68, -0.6, 0.32, 1.6"
            ];

            flash = {
              flash_opacity = 0.92;
              in_bezier = "easeInOutBack";
              in_speed = 0.5;
              out_bezier = "easeInOutBack";
              out_speed = 3;
            };

            shrink = {
              shrink_percentage = 0.99;
              in_bezier = "easeInOutBack";
              in_speed = 1.5;
              out_bezier = "easeInOutBack";
              out_speed = 3;
            };
          };

          # --- Decoration ---
          decoration = {
            rounding = 0;
          };
        };

        # --- Core Keybinds (Application Launchers, Screenshots, etc.) ---
        bind =
          [
            # --- Applications ---
            "${mainMod}, RETURN, exec, ${pkgs.kitty}/bin/kitty"
            "${mainMod}, D, exec, ${pkgs.wofi}/bin/wofi --show drun"
            "${mainMod}, A, exec, rofi-rbw"
            "${mainMod}, E, exec, ${pkgs.rofi-emoji-wayland}/bin/rofi-emoji-wayland"
            "${mainMod} SHIFT, Q, killactive,"
            "${mainMod}, Z, exec, ${pkgs.grim}/bin/grim -g \"$(${pkgs.slurp}/bin/slurp)\" - | ${pkgs.wl-clipboard}/bin/wl-copy -t image/png"
            "${mainMod} SHIFT, Z, exec, ${pkgs.grim}/bin/grim - | ${pkgs.wl-clipboard}/bin/wl-copy -t image/png"
            "${mainMod}, Print, exec, blinkstick-scripts white"
            "${mainMod} SHIFT, Print, exec, blinkstick-scripts off"
            "${mainMod} SHIFT, L, exec, systemctl suspend"

            # --- Workspace Management ---
          ]
          ++ (lib.genList (i: "${mainMod}, ${toString (i + 1)}, workspace, ${toString (i + 1)}") 9) # Workspaces 1-9
          ++ ["${mainMod}, 0, workspace, 10"] # Workspace 0 -> 10
          ++ (lib.genList (i: "${mainMod} SHIFT, ${toString (i + 1)}, movetoworkspace, ${toString (i + 1)}") 9) # Move to 1-9
          ++ ["${mainMod} SHIFT, 0, movetoworkspace, 10"] # Move to 0 -> 10
          ++ [
            "${mainMod} SHIFT CTRL, 1, movetoworkspacesilent, 1"

            # Scroll through existing workspaces
            "${mainMod}, mouse_down, workspace, e+1"
            "${mainMod}, mouse_up, workspace, e-1"

            # --- Other Useful Binds ---
            "${mainMod}, F, fullscreen, 0"
            "${mainMod} SHIFT, S, togglefloating,"

            # --- Binds to ENTER submaps ---
            "${mainMod}, R, submap, resizeWindow"
            "${mainMod}, S, submap, preselectSplit"
          ];

        # --- Mouse Bindings ---
        bindm = [
          "${mainMod}, mouse:272, movewindow"
          "${mainMod}, mouse:273, resizewindow"
        ];
      };
    };
  };
}
