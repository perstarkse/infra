{
  config.flake.homeModules.waybar = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.waybar;

    commonModules = {
      "network" = {
        "interface" = "se-mma-wg-001";
        "format" = "{ifname}"; # Example: "se-mma-wg-001 🔒"
        "format-disconnected" = "VPN Off";
        "tooltip-format" = "VPN: {ifname}\nIP: {ipaddr}/{cidr}";
        "on-click" = "dunstify 'External IP' \"$(LANG=C curl -sf ifconfig.me || echo 'N/A (check connection)')\"";
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
      clock = {
        format = "{:%H:%M}  ";
        format-alt = "{:%A, %B %d, %Y (%R)}  ";
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
        "format" = " {status}";
        "format-connected" = " {device_alias}";
        "format-connected-battery" = " {device_alias} {device_battery_percentage}%";
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
    };

    hyprlandModules = {
      "hyprland/workspaces" = {
        "format" = "{icon}";
        "on-scroll-up" = "hyprctl dispatch workspace e+1";
        "on-scroll-down" = "hyprctl dispatch workspace e-1";
      };
      "hyprland/window" = {
        "format" = "{}";
        "rewrite" = {
          "(.*) — qutebrowser " = "🌎 $1";
          "(.*) - fish" = "> [$1]";
        };
        "separate-outputs" = true;
      };
      "hyprland/language" = {
        "format" = "xkb: {}";
      };
    };

    swayModules = {
      "sway/workspaces" = {
        "format" = "{icon}";
        "on-scroll-up" = "swaymsg workspace next";
        "on-scroll-down" = "swaymsg workspace prev";
      };
      "sway/window" = {
        "format" = "{}";
        "rewrite" = {
          "(.*) — qutebrowser " = "🌎 $1";
          "(.*) - fish" = "> [$1]";
        };
        "separate-outputs" = true;
      };
      "sway/language" = {
        "format" = "xkb: {}";
      };
    };

    niriModules = {
      "niri/workspaces" = {
        "format" = "{icon}";
        "on-scroll-up" = "niri msg action focus-workspace-up";
        "on-scroll-down" = "niri msg action focus-workspace-down";
      };
      "niri/window" = {
        "format" = "{}";
        "rewrite" = {
          "(.*) — qutebrowser " = "🌎 $1";
          "(.*) - fish" = "> [$1]";
        };
        "separate-outputs" = true;
      };
      "niri/language" = {
        "format" = "xkb: {}";
      };
    };

    wmModules =
      if cfg.windowManager == "hyprland"
      then hyprlandModules
      else if cfg.windowManager == "sway"
      then swayModules
      else niriModules;
    wmWorkspaces =
      if cfg.windowManager == "hyprland"
      then "hyprland/workspaces"
      else if cfg.windowManager == "sway"
      then "sway/workspaces"
      else "niri/workspaces";
    wmWindow =
      if cfg.windowManager == "hyprland"
      then "hyprland/window"
      else if cfg.windowManager == "sway"
      then "sway/window"
      else "niri/window";
    wmLanguage =
      if cfg.windowManager == "hyprland"
      then "hyprland/language"
      else if cfg.windowManager == "sway"
      then "sway/language"
      else "niri/language";
  in {
    options = {
      my.waybar = {
        windowManager = lib.mkOption {
          type = lib.types.enum ["hyprland" "sway" "niri"];
          default = "hyprland";
          description = "The window manager to configure Waybar for";
        };
      };
    };

    config = {
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
            padding: 0;
            margin: 0;
          }
        '';
        settings = {
          mainBar =
            {
              layer = "top";
              position = "bottom";
              height = 20;
              modules-left = [wmWorkspaces];
              modules-center = [wmWindow];
              modules-right = ["network" "disk" wmLanguage "bluetooth" "pulseaudio" "clock" "privacy"];
            }
            // commonModules // wmModules;
        };
      };
    };
  };
}
