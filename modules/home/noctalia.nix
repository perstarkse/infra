{inputs, ...}: {
  config.flake.homeModules.noctalia = {
    lib,
    config,
    pkgs,
    ...
  }: let
    cfg = config.my.noctalia;
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
            # backgroundOpacity = 1;  # set by upstream Nix module
            marginVertical = 0;
            marginHorizontal = 0;
            frameThickness = 0;
            widgets = {
              left = [
                {
                  id = "Launcher";
                  useDistroLogo = true;
                }
                {
                  id = "Clock";
                  formatHorizontal = "HH:mm";
                  formatVertical = "HH\nmm";
                  useMonospacedFont = true;
                }
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
            # panelBackgroundOpacity = 0.93;
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
                {
                  id = "NoctaliaPerformance";
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
            # backgroundOpacity = 1;
            respectExpireTimeout = false;
            lowUrgencyDuration = 5;
            normalUrgencyDuration = 8;
            criticalUrgencyDuration = 0;
            sounds.enabled = false;
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
            # backgroundOpacity = 1;
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
          dock.enabled = true;
          plugins = {
            autoUpdate = false;
            notifyUpdates = true;
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
          states = {};
          version = 2;
        };
      };

      my.niri.extraSpawnAtStartup = [["noctalia-shell"]];

      home.packages = with pkgs; [
        libsForQt5.qt5.qtwayland
        qt6.qtwayland
      ];
    };
  };
}
