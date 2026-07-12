{
  config.flake.nixosModules.ddcutil = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.ddcutil;
    monitorCfg = cfg.monitor;

    # systemd-sleep hooks run with a minimal environment: no PATH (uname -m fails)
    # and no HOME/XDG_CACHE_HOME (dynamic sleep cache path cannot be resolved).
    ddcutilWrapper = pkgs.writeShellScriptBin "ddcutil" ''
      export PATH="${lib.makeBinPath [pkgs.coreutils pkgs.ddcutil]}:$PATH"
      export XDG_CACHE_HOME="''${XDG_CACHE_HOME:-/var/cache/ddcutil}"
      export HOME="''${HOME:-/root}"
      exec ${pkgs.ddcutil}/bin/ddcutil "$@"
    '';

    monitorDataPackage =
      if monitorCfg.enable
      then
        pkgs.runCommand "ddcutil-monitor-data" {} ''
          mkdir -p $out
          cp -r ${monitorCfg.dataDir}/. $out/
        ''
      else null;

    commonScriptSubstitutions = [
      "@MONITOR_DIR@"
      "@DISPLAY_NUM@"
      "@YQ@"
      "@DDCUTIL@"
    ];

    commonScriptReplacements = [
      "${monitorDataPackage}"
      (toString monitorCfg.display)
      "${pkgs.yq-go}/bin/yq"
      "${ddcutilWrapper}/bin/ddcutil"
    ];

    resumeScriptSubstitutions = [
      "@DISPLAY_NUM@"
      "@MAX_ATTEMPTS@"
      "@RETRY_INTERVAL@"
      "@RESUME_ON_LOCAL_WAKE_ONLY@"
      "@RESUME_WAIT_SECONDS@"
      "@REMOTE_WAKE_USER@"
      "@LOGINCTL@"
      "@AWK@"
      "@JOURNALCTL@"
      "@GREP@"
      "@TIMEOUT@"
      "@DD@"
      "@SLEEP@"
      "@LOGGER@"
      "@SEQ@"
      "@DDCUTIL@"
    ];

    resumeScriptReplacements = [
      (toString monitorCfg.display)
      (toString monitorCfg.resumeMaxAttempts)
      (toString monitorCfg.resumeRetrySeconds)
      (
        if monitorCfg.resumeOnLocalWakeOnly
        then "true"
        else "false"
      )
      (toString monitorCfg.resumeRemoteWakeWaitSeconds)
      (monitorCfg.remoteWakeUser or "")
      "${pkgs.systemd}/bin/loginctl"
      "${pkgs.gawk}/bin/awk"
      "${pkgs.systemd}/bin/journalctl"
      "${pkgs.gnugrep}/bin/grep"
      "${pkgs.coreutils}/bin/timeout"
      "${pkgs.coreutils}/bin/dd"
      "${pkgs.coreutils}/bin/sleep"
      "${pkgs.util-linux}/bin/logger"
      "${pkgs.coreutils}/bin/seq"
      "${ddcutilWrapper}/bin/ddcutil"
    ];

    substituteScript = name: scriptPath:
      pkgs.writeShellScriptBin name
      (lib.replaceStrings commonScriptSubstitutions commonScriptReplacements (builtins.readFile scriptPath));

    substituteResumeScript =
      pkgs.writeShellScriptBin "monitor-resume"
      (lib.replaceStrings resumeScriptSubstitutions resumeScriptReplacements (builtins.readFile ./scripts/resume.sh));

    monitorPower = substituteScript "monitor-power" ./scripts/power.sh;
    monitorResume = substituteResumeScript;

    systemSuspend =
      pkgs.writeShellScriptBin "system-suspend" (builtins.readFile ./scripts/suspend.sh);
  in {
    options.my.ddcutil = {
      enable = lib.mkEnableOption "DDC/CI monitor control via ddcutil";

      ddcui = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Install the ddcui graphical frontend.";
      };

      monitor = lib.mkOption {
        type = lib.types.submodule {
          options = {
            enable = lib.mkEnableOption "monitor-profile and monitor-power commands";

            dataDir = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = ''
                Machine-local monitor data (monitor.yaml with picture_modes).
              '';
            };

            display = lib.mkOption {
              type = lib.types.int;
              default = 1;
              description = "ddcutil display number (-d).";
            };

            resumeMaxAttempts = lib.mkOption {
              type = lib.types.int;
              default = 20;
              description = ''
                Resume attempts for monitor-power on after system sleep.
                Each attempt uses ddcutil --maxtries 1,1,1 for a fast probe.
              '';
            };

            resumeRetrySeconds = lib.mkOption {
              type = lib.types.float;
              default = 0.25;
              description = "Seconds between resume attempts when I2C is not ready yet.";
            };

            resumeOnLocalWakeOnly = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = ''
                Turn the monitor on after resume only for local wakes (keyboard, power button).
                Remote wakes (for example wake-proxy keep-awake SSH) skip monitor power-on.
              '';
            };

            resumeRemoteWakeWaitSeconds = lib.mkOption {
              type = lib.types.float;
              default = 5.0;
              description = ''
                Seconds to wait after resume for remote wake signals before skipping monitor
                power-on. Keyboard and power-button wakes are detected sooner when possible.
              '';
            };

            remoteWakeUser = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = "wakeproxy-keep-awake";
              example = "wakeproxy-keep-awake";
              description = ''
                Login user that indicates a remote wake-proxy keep-awake session.
                Set to null to disable this signal.
              '';
            };
          };
        };
        default = {};
      };
    };

    config = lib.mkIf cfg.enable (lib.mkMerge [
      {
        hardware.i2c.enable = true;

        users.users.${config.my.mainUser.name}.extraGroups = ["i2c"];

        environment.systemPackages =
          [ddcutilWrapper]
          ++ lib.optional cfg.ddcui pkgs.ddcui;

        systemd.tmpfiles.rules = [
          "d /var/cache/ddcutil 0755 root root -"
        ];
      }
      (lib.mkIf monitorCfg.enable {
        assertions = [
          {
            assertion = monitorCfg.dataDir != null;
            message = "my.ddcutil.monitor.dataDir must be set when monitor scripts are enabled.";
          }
        ];

        environment.systemPackages = [
          (substituteScript "monitor-profile" ./scripts/profile.sh)
          monitorPower
          systemSuspend
          pkgs.yq-go
        ];

        environment.etc."systemd/system-sleep/monitor-power" = {
          source = pkgs.writeShellScript "monitor-power-resume" ''
            case "$1" in
              pre)
                ${pkgs.coreutils}/bin/date -Iseconds > /run/monitor-power-suspend-since || true
                idle_hint=yes
                for session in $(${pkgs.systemd}/bin/loginctl list-sessions --no-legend | ${pkgs.gawk}/bin/awk '{print $1}'); do
                  session_type=$(${pkgs.systemd}/bin/loginctl show-session "$session" -p Type --value 2>/dev/null || true)
                  session_class=$(${pkgs.systemd}/bin/loginctl show-session "$session" -p Class --value 2>/dev/null || true)
                  if { [ "$session_type" = "wayland" ] || [ "$session_type" = "x11" ]; } \
                    && [ "$session_class" = "user" ]; then
                    idle_hint=$(${pkgs.systemd}/bin/loginctl show-session "$session" -p IdleHint --value 2>/dev/null || echo "yes")
                    break
                  fi
                done
                echo "$idle_hint" > /run/monitor-power-suspend-idle-hint || true
                ;;
              post)
                exec ${monitorResume}/bin/monitor-resume
                ;;
            esac
          '';
          mode = "0755";
        };
      })
    ]);
  };
}
