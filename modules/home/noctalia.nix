{inputs, ...}: {
  config.flake.homeModules.noctalia = {
    lib,
    config,
    pkgs,
    ...
  }: let
    inherit (pkgs.stdenv.hostPlatform) system;
    cfg = config.my.noctalia;
    noctaliaPkg = inputs.noctalia.packages.${system}.default;
    voxtypePkg = config.programs.voxtype.package or null;
    launcherPath = lib.concatStringsSep ":" (
      lib.filter (p: p != "") [
        "${noctaliaPkg}/bin"
        (lib.optionalString (voxtypePkg != null) "${voxtypePkg}/bin")
      ]
    );
    noctaliaLauncher = pkgs.writeShellScriptBin "noctalia-shell-session" ''
      export PATH="${launcherPath}:$PATH"
      exec ${lib.getExe noctaliaPkg} "$@"
    '';
  in {
    imports = [inputs.noctalia.homeModules.default];

    options.my.noctalia = {
      enable = lib.mkEnableOption "Noctalia desktop shell";
    };

    config = lib.mkIf cfg.enable {
      programs.noctalia-shell = {
        enable = true;
        settings = {
          bar = {
            position = "top";
            density = "compact";
            showOutline = false;
            showCapsule = false;
            outerCorners = false;
            frameRadius = 0;
            marginVertical = 0;
            marginHorizontal = 0;
            frameThickness = 0;
            widgets = {
              left = [
                {
                  id = "SystemMonitor";
                }
                {
                  id = "ActiveWindow";
                }
                {
                  id = "MediaMini";
                }
              ];
              center = [
                {
                  id = "Workspace";
                  labelMode = "none";
                  hideUnoccupied = false;
                }
              ];
              right = [
                {
                  id = "Tray";
                }
                {
                  id = "NotificationHistory";
                }
                {
                  id = "Battery";
                  alwaysShowPercentage = false;
                  warningThreshold = 20;
                }
                {
                  id = "Volume";
                }
                {
                  id = "ControlCenter";
                }
                {
                  id = "plugin:voxtype-status";
                }
                {
                  id = "Clock";
                  formatHorizontal = "HH:mm";
                  formatVertical = "HH\nmm";
                  useMonospacedFont = true;
                }
              ];
            };
          };
          general = {
            avatarImage = "";
            dimmerOpacity = 0.2;
            showScreenCorners = false;
            scaleRatio = 1;
            radiusRatio = 0;
            animationSpeed = 1;
            enableShadows = false;
            enableBlurBehind = true;
            enableLockScreenMediaControls = false;
            lockOnSuspend = true;
            showChangelogOnStartup = false;
            telemetryEnabled = false;
          };
          ui = {
            tooltipsEnabled = true;
            scrollbarAlwaysVisible = true;
            panelsAttachedToBar = true;
            settingsPanelMode = "attached";
          };
          location = {
            weatherEnabled = true;
            useFahrenheit = false;
            use12hourFormat = false;
            showWeekNumberInCalendar = false;
            showCalendarEvents = true;
            showCalendarWeather = true;
            autoLocate = true;
          };
          controlCenter = {
            position = "close_to_bar_button";
            diskPath = "/";
            shortcuts = {
              left = [
                {
                  id = "Bluetooth";
                }
                {
                  id = "WallpaperSelector";
                }
              ];
              right = [
                {
                  id = "Notifications";
                }
                {
                  id = "PowerProfile";
                }
                {
                  id = "KeepAwake";
                }
                {
                  id = "NightLight";
                }
              ];
            };
            cards = [
              {
                enabled = false;
                id = "profile-card";
              }
              {
                enabled = true;
                id = "shortcuts-card";
              }
              {
                enabled = true;
                id = "audio-card";
              }
              {
                enabled = false;
                id = "brightness-card";
              }
              {
                enabled = true;
                id = "weather-card";
              }
              {
                enabled = true;
                id = "media-sysmon-card";
              }
            ];
          };
          notifications = {
            enabled = true;
            location = "top_right";
            density = "default";
            respectExpireTimeout = false;
            lowUrgencyDuration = 5;
            normalUrgencyDuration = 8;
            criticalUrgencyDuration = 0;
            sounds.enabled = true;
          };
          appLauncher = {
            position = "center";
            pinnedApps = [];
            sortByMostUsed = true;
            terminalCommand = "kitty -e";
            viewMode = "list";
            showCategories = true;
            showSettingsSearch = true;
            showWindowsSearch = true;
            showSessionSearch = true;
            density = "compact";
          };
          sessionMenu = {
            enableCountdown = true;
            countdownDuration = 10000;
            position = "center";
            showHeader = true;
            showKeybinds = true;
            powerOptions = [
              {
                action = "lock";
                enabled = true;
                keybind = "1";
              }
              {
                action = "suspend";
                enabled = true;
                keybind = "2";
              }
              {
                action = "hibernate";
                enabled = true;
                keybind = "3";
              }
              {
                action = "reboot";
                enabled = true;
                keybind = "4";
              }
              {
                action = "logout";
                enabled = true;
                keybind = "5";
              }
              {
                action = "shutdown";
                enabled = true;
                keybind = "6";
              }
              {
                action = "rebootToUefi";
                enabled = true;
                keybind = "7";
              }
            ];
          };
          wallpaper = {
            enabled = false;
            useSolidColor = true;
            solidColor = "#000000";
          };
          osd = {
            enabled = true;
            location = "top_right";
            autoHideMs = 2000;
          };
          audio = {
            volumeStep = 5;
            volumeOverdrive = false;
            mprisBlacklist = [];
            volumeFeedback = false;
          };
          brightness = {
            brightnessStep = 5;
            enforceMinimum = true;
          };
          colorSchemes = {
            useWallpaperColors = false;
            predefinedScheme = "Noctalia (default)";
            darkMode = true;
            schedulingMode = "off";
            syncGsettings = true;
          };
          systemMonitor = {
            cpuWarningThreshold = 80;
            cpuCriticalThreshold = 90;
            memWarningThreshold = 80;
            memCriticalThreshold = 90;
            batteryWarningThreshold = 20;
            batteryCriticalThreshold = 5;
          };
          dock.enabled = false;
          plugins = {
            autoUpdate = false;
            notifyUpdates = false;
          };
          nightLight = {
            enabled = false;
            autoSchedule = true;
            nightTemp = "4000";
            dayTemp = "6500";
          };
          idle = {
            enabled = false;
          };
        };
        plugins = {
          sources = [
            {
              enabled = true;
              name = "Official Noctalia Plugins";
              url = "https://github.com/noctalia-dev/noctalia-plugins";
            }
          ];
          states = {
            "voxtype-status" = {
              enabled = true;
            };
          };
          version = 2;
        };
      };

      xdg.configFile."noctalia/plugins/voxtype-status" = {
        source = pkgs.fetchzip {
          url = "https://github.com/phumberdroz/voxtype-noctalia/archive/6a86b469feef97d957ea03995d6d1d592253949d.tar.gz";
          hash = "sha256-s0r803u+E4ZIsiXaTcsq8fo5dwKhhNyw/7qPVtOp+lU=";
          stripRoot = true;
        };
      };

      my.niri.extraSpawnAtStartup = [["noctalia-shell-session"]];

      home.activation.removeVoxtypePluginBackup = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/rm -rf "${config.xdg.configHome}/noctalia/plugins/voxtype-status.backup"
      '';

      # Quickshell only loads plugins at startup; restart after deploy so bar widgets pick up changes.
      home.activation.restartNoctaliaShell = lib.hm.dag.entryAfter ["writeBoundary"] ''
        if ${pkgs.procps}/bin/pgrep -x quickshell >/dev/null \
          || ${pkgs.procps}/bin/pgrep -f "bin/noctalia-shell" >/dev/null; then
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/killall quickshell 2>/dev/null || true
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/killall noctalia-shell 2>/dev/null || true
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/sleep 0.5
        fi
        if ! ${pkgs.procps}/bin/pgrep -x quickshell >/dev/null; then
          $DRY_RUN_CMD ${lib.getExe noctaliaLauncher} >/dev/null 2>&1 &
        fi
      '';

      home.packages = with pkgs; [
        libsForQt5.qt5.qtwayland
        qt6.qtwayland
        noctaliaLauncher
      ];
    };
  };
}
