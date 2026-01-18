{
  config.flake.homeModules.waybar = {
    lib,
    config,
    pkgs,
    ...
  }: let
    cfg = config.my.waybar;
    niriCfg = lib.attrByPath ["my" "niri"] {} config;
    niriWorkspaceNames = niriCfg.workspaceNames or [];
    defaultWorkspaceIconsByName = {
      "1:main" = "";
      "2:web" = "";
      "3:code" = "";
      "4:chat" = "";
      "5:media" = "";
      "6:games" = "";
      "7:build" = "";
      "8:vm" = "";
      "9:misc" = "";
      "10:scratch" = "";
    };
    generatedWorkspaceIcons =
      lib.listToAttrs
      (map
        (name: let
          fallbackParts = lib.splitString ":" name;
          fallback =
            if fallbackParts == []
            then name
            else lib.head fallbackParts;
        in {
          inherit name;
          value =
            lib.attrByPath [name] fallback defaultWorkspaceIconsByName;
        })
        niriWorkspaceNames);
    customWorkspaceIcons = niriCfg.workspaceIcons or {};
    niriFormatIcons =
      generatedWorkspaceIcons
      // defaultWorkspaceIconsByName
      // customWorkspaceIcons
      // {
        default = "";
        active = "";
        urgent = "";
      };

    vramScript = pkgs.writeShellScriptBin "waybar-vram" ''
      # Calculate VRAM usage from fdinfo (Deduplicate by PID, Sum Private + Max Shared)
      grep -H "drm-resident-vram0:\|drm-shared-vram0:" /proc/*/fdinfo/* 2>/dev/null | \
      awk -F: '
        {
          # Extract PID from filename (e.g. /proc/1234/fdinfo/5 -> 1234)
          split($1, path, "/")
          pid = path[3]

          # Parse value and unit
          val = $3 + 0
          unit = "B"
          if ($3 ~ /GiB/) unit = "GiB"
          else if ($3 ~ /MiB/) unit = "MiB"
          else if ($3 ~ /KiB/) unit = "KiB"

          if (unit == "KiB") val *= 1024
          else if (unit == "MiB") val *= 1048576
          else if (unit == "GiB") val *= 1073741824

          # Store max value seen for this PID (handles duplicate FDs)
          if ($2 ~ "resident") {
            if (val > res[pid]) res[pid] = val
          }
          if ($2 ~ "shared") {
            if (val > shr[pid]) shr[pid] = val
          }
        }
        END {
          priv = 0
          max_shr = 0
          for (p in res) {
            r = res[p]
            s = shr[p] + 0 # ensure numeric
            
            # Private = Resident - Shared
            if (s > r) s = r
            
            priv += (r - s)
            if (s > max_shr) max_shr = s
          }
          printf "%.1f GB", (priv + max_shr) / 1073741824
        }
      '
    '';

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
      "memory" = {
        "interval" = 10;
        "format" = "RAM: {used:0.1f}/{total:0.1f} GB";
        "tooltip-format" = "{percentage}% used";
      };
      "custom/vram" = {
        "interval" = 5;
        "exec" = "${vramScript}/bin/waybar-vram";
        "format" = "GPU: {}";
        "tooltip" = false;
      };
      "cpu" = {
        "interval" = 10;
        "format" = "CPU: {usage}%";
        "tooltip" = true;
      };
      "temperature" = {
        "critical-threshold" = 80;
        "format" = "{temperatureC}°C";
        "format-critical" = "{temperatureC}°C ";
      };
      "custom/backup" = {
        "interval" = 60;
        "exec" = "systemctl show restic-backups-documents.service --property=SubState,Result --value | xargs | awk '{if($1==\"running\") print \"Backup: \"; else if($2==\"success\") print \"Backup: \"; else print \"Backup:  \" $2}'";
        "format" = "{}";
      };
      "mpris" = {
        "format" = "{player_icon} {dynamic}";
        "format-paused" = "{status_icon} <i>{dynamic}</i>";
        "player-icons" = {
          "default" = "▶";
          "mpv" = "🎵";
        };
        "status-icons" = {
          "paused" = "⏸";
        };
      };
      "disk" = {
        "interval" = 30;
        "format" = "{specific_free:0.2f}/{specific_total:0.2f} GB";
        "unit" = "GB";
        "on-click" = "${pkgs.kitty}/bin/kitty -e ${pkgs.ncdu}/bin/ncdu ~";
      };
      "custom/voxtype" = {
        "exec" = "voxtype status --follow --format json";
        "return-type" = "json";
        "format" = "{}";
        "tooltip" =
          true;
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
        "tooltip" = true;
        "tooltip-format" = "{name}";
        "on-click" = "niri msg action focus-workspace {name}";
        "on-click-right" = "niri msg action move-column-to-workspace {name}";
        "on-scroll-up" = "niri msg action focus-workspace-up";
        "on-scroll-down" = "niri msg action focus-workspace-down";
        "format-icons" = niriFormatIcons;
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
      home.packages = [pkgs.ncdu];
      
      # Fix for multiple Waybar instances after monitor sleep
      # The Tray module often causes Waybar to hang on output disconnect.
      # These settings ensure Systemd aggressively cleans up the old hung process
      # before allowing a new one to stack on top.
      systemd.user.services.waybar.Service = {
        Restart = "on-failure";
        KillMode = "mixed";
        TimeoutStopSec = "5s";
      };

      programs.waybar = {
        enable = true;
        systemd = {
          enable = true;
          target = "graphical-session.target";
        };
        style = ''
          #workspaces {
            padding: 0;
            margin: 0;
          }

          #workspaces button {
            padding: 0 10px;
            margin: 0 2px;
            min-height: 0;
            min-width: 0;
            border: none;
            border-radius: 0;
            background: transparent;
          }

          #workspaces button:hover {
            background-color: rgba(255, 255, 255, 0.08);
          }

          #workspaces button.focused,
          #workspaces button.active {
            border: none;
            box-shadow: none;
          }

          #workspaces button.urgent {
            box-shadow: inset 0 -1px 0 0 #ff6c6b;
          }
          #custom-backup {
            padding-right: 8px;
          }
        '';
        settings = {
          mainBar =
            {
              layer = "top";
              position = "top";
              height = 20;
              modules-left = [wmWorkspaces];
              modules-center = [wmWindow "mpris"];
              modules-right = ["network" "memory" "cpu" "temperature" "disk" "custom/backup" wmLanguage "bluetooth" "pulseaudio" "clock" "custom/voxtype" "privacy"];
            }
            // commonModules // wmModules;
        };
      };
    };
  };
}
