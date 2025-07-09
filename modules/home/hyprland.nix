{
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

    programs.waybar = {
      enable = true;
      systemd = {
        enable = true;
        target = "graphical-session.target";
      };
      style = ''
        #workspaces button {
          padding: 0;
          margin: 0;
          min-height: 0;
          border: none;
          border-radius: 0;
        }

        #workspaces button.active {
          border-bottom: 1px solid @base05;
        }

        #workspaces {
          padding: 0; /* Remove padding from the workspaces container */
          margin: 0;
        }
      '';
      settings = {
        mainBar = {
          layer = "top";
          position = "bottom";
          height = 20;
          modules-left = ["hyprland/workspaces"];
          modules-center = ["hyprland/window"];
          modules-right = ["network" "disk" "hyprland/language" "bluetooth" "pulseaudio" "clock" "privacy"];
          "network" = {
            # Monitor active network interfaces whose names start with "wg".
            "interface" = "se-mma-wg-001";

            # Format to display when a WireGuard interface (matching "wg*") is active
            # and has an IP address. {ifname} will be the name of the WireGuard interface.
            "format" = "{ifname}"; # Example: "se-mma-wg-001 🔒"

            # Format to display when no interface matching "wg*" is active or has an IP.
            # This indicates the VPN is disconnected or not established.
            "format-disconnected" = "VPN Off";

            # Tooltip to show on hover when a WireGuard interface is active.
            # This will show the IP address assigned to the WireGuard interface itself.
            "tooltip-format" = "VPN: {ifname}\nIP: {ipaddr}/{cidr}";

            # Command to execute on click: shows external IP using notify-send.
            # Make sure 'curl' and 'libnotify' (for notify-send) are installed.
            "on-click" = "dunstify 'External IP' \"$(LANG=C curl -sf ifconfig.me || echo 'N/A (check connection)')\"";

            # How often to check the network status, in seconds.
            "interval" = 10;
          };
          "privacy" = {
            "icon-spacing" = 4;
            "icon-size" = 18;
            "transition-duration" = 250;
            "modules" = [
              {
                "type" = "screenshare";
                "tooltip" = true;
                "tooltip-icon-size" = 24;
              }
              {
                "type" = "audio-out";
                "tooltip" = true;
                "tooltip-icon-size" = 24;
              }
              {
                "type" = "audio-in";
                "tooltip" = true;
                "tooltip-icon-size" = 24;
              }
            ];
          };
          "hyprland/language" = {
            "format" = "xkb: {}";
          };
          "hyprland/window" = {
            "format" = "{}";
            "rewrite" = {
              "(.*) — qutebrowser " = "🌎 $1";
              "(.*) - fish" = "> [$1]";
            };
            "separate-outputs" = true;
          };
          clock = {
            format = "{:%H:%M}  ";
            format-alt = "{:%A, %B %d, %Y (%R)}  ";
            tooltip-format = "<tt><small>{calendar}</small></tt>";
            calendar = {
              mode = "year";
              mode-mon-col = 3;
              weeks-pos = "right";
              on-scroll = 1;
              format = {
                months = "<span color='#ffead3'><b>{}</b></span>";
                days = "<span color='#ecc6d9'><b>{}</b></span>";
                weeks = "<span color='#99ffdd'><b>W{}</b></span>";
                weekdays = "<span color='#ffcc66'><b>{}</b></span>";
                today = "<span color='#ff6699'><b><u>{}</u></b></span>";
              };
            };
            actions = {
              on-click-right = "mode";
              on-scroll-up = "shift_up";
              on-scroll-down = "shift_down";
            };
          };
          "bluetooth" = {
            "format" = " {status}";
            "format-connected" = " {device_alias}";
            "format-connected-battery" = " {device_alias} {device_battery_percentage}%";
            "tooltip-format" = "{controller_alias}\t{controller_address}\n\n{num_connections} connected";
            "tooltip-format-connected" = "{controller_alias}\t{controller_address}\n\n{num_connections} connected\n\n{device_enumerate}";
            "tooltip-format-enumerate-connected" = "{device_alias}\t{device_address}";
            "tooltip-format-enumerate-connected-battery" = "{device_alias}\t{device_address}\t{device_battery_percentage}%";
          };
          "disk" = {
            "interval" = 30;
            "format" = "{specific_free:0.2f}/{specific_total:0.2f} GB";
            "unit" = "GB";
          };
          "hyprland/workspaces" = {
            "format" = "{icon}";
            # "format-icons" = { "active" = ""; "default" = "" "urgent" = "" "empty" = "" };
            "on-scroll-up" = "hyprctl dispatch workspace e+1";
            "on-scroll-down" = "hyprctl dispatch workspace e-1";
          };
        };
      };
    };

    programs.kitty.enable = true;

    home.packages = with pkgs; [
      # Ensure necessary packages are available
      kitty
      wofi
      grim
      slurp
      wl-clipboard
    ];

    wayland.windowManager.hyprland = {
      enable = true;
      plugins = [
        # pkgs.mynixpkgs.hyprlandPlugins.hyprfocus
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
        ];

        # --- Monitor Configuration ---
        monitor = [
          "DP-1, 3440x1440@143.85, 0x0, 1, vrr, 1"
        ];

        # --- General ---
        general = {
          gaps_in = 0;
          gaps_out = 0;
          border_size = 1;
          layout = "dwindle";
        };

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
        };

        # --- Decoration ---
        decoration = {
          rounding = 0;
        };

        # --- Dwindle Layout ---
        dwindle = {
          pseudotile = true;
          preserve_split = true;
          force_split = 2;
          # smart_split = false; # Not in your original active config
          # smart_resizing = true; # Not in your original active config
        };

        # --- Keybinds (Global, not inside specific submap definitions) ---
        bind =
          [
            # --- Applications ---
            "${mainMod}, RETURN, exec, ${pkgs.kitty}/bin/kitty"
            "${mainMod}, D, exec, ${pkgs.wofi}/bin/wofi --show drun"
            # "${mainMod}, A, exec, ${pkgs.rofi-rbw}/bin/rofi-rbw"
            # "${mainMod}, E, exec, ${pkgs.rofi}/bin/rofi -modi emoji -show emoji"
            "${mainMod} SHIFT, Q, killactive,"
            "${mainMod}, Z, exec, ${pkgs.grim}/bin/grim -g \"$(${pkgs.slurp}/bin/slurp)\" - | ${pkgs.wl-clipboard}/bin/wl-copy -t image/png"
            "${mainMod} SHIFT, Z, exec, ${pkgs.grim}/bin/grim - | ${pkgs.wl-clipboard}/bin/wl-copy -t image/png"
            "${mainMod}, Print, exec, blinkstick-scripts white"
            "${mainMod} SHIFT, Print, exec, blinkstick-scripts off"
            "${mainMod} SHIFT, L, exec, systemctl suspend"

            # --- Window Focus ---
            "${mainMod}, H, movefocus, l"
            "${mainMod}, J, movefocus, d"
            "${mainMod}, K, movefocus, u"
            "${mainMod}, L, movefocus, r"
            "${mainMod}, left, movefocus, l"
            "${mainMod}, right, movefocus, r"
            "${mainMod}, up, movefocus, u"
            "${mainMod}, down, movefocus, d"

            # --- Move Active Window ---
            "${mainMod} SHIFT, H, movewindow, l"
            "${mainMod} SHIFT, J, movewindow, d"
            "${mainMod} SHIFT, K, movewindow, u"
            "${mainMod} SHIFT, L, movewindow, r"
            "${mainMod} SHIFT, left, movewindow, l"
            "${mainMod} SHIFT, right, movewindow, r"
            "${mainMod} SHIFT, up, movewindow, u"
            "${mainMod} SHIFT, down, movewindow, d"

            # --- Workspace Management ---
          ]
          ++ (lib.genList (i: "${mainMod}, ${toString (i + 1)}, workspace, ${toString (i + 1)}") 9) # Workspaces 1-9
          ++ ["${mainMod}, 0, workspace, 10"] # Workspace 0 -> 10
          ++ (lib.genList (i: "${mainMod} SHIFT, ${toString (i + 1)}, movetoworkspace, ${toString (i + 1)}") 9) # Move to 1-9
          ++ ["${mainMod} SHIFT, 0, movetoworkspace, 10"] # Move to 0 -> 10
          ++ [
            "${mainMod} SHIFT CTRL, 1, movetoworkspacesilent, 1" # Example

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

      # --- Submap definitions and their internal binds ---
      # These are best kept in extraConfig to ensure correct sequential parsing by Hyprland.
      extraConfig = ''
        # --- Resize Tiled Windows (Faster, with Arrow Keys) ---
        submap = resizeWindow
        binde=, right, resizeactive, 30 0
        binde=, left, resizeactive, -30 0
        binde=, up, resizeactive, 0 -30
        binde=, down, resizeactive, 0 30
        # You can also add HJKL here if you want both:
        # binde=, L, resizeactive, 30 0
        # binde=, H, resizeactive, -30 0
        # binde=, K, resizeactive, 0 -30
        # binde=, J, resizeactive, 0 30
        bind=, escape, submap, reset # Exit submap
        bind =, return, submap, reset # Enter also exists
        submap = reset # Marks end of submap definition for Hyprland parser

        # --- Dwindle Layout: Preselect Split Direction ---
        submap = preselectSplit
        bind =, L, layoutmsg, presel r, submap, reset
        bind =, H, layoutmsg, presel l, submap, reset
        bind =, K, layoutmsg, presel u, submap, reset
        bind =, J, layoutmsg, presel d, submap, reset
        bind =, escape, submap, reset # Escape also exits
        bind =, return, submap, reset # Enter also exists
        submap = reset # Marks end of submap definition
      '';
    };
  };
}
