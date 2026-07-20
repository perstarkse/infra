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
      "@KEEP_AWAKE_STATE_DIR@"
      "@KEEP_AWAKE_UNIT@"
      "@DATE@"
      "@AWK@"
      "@JOURNALCTL@"
      "@GREP@"
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
      monitorCfg.keepAwakeStateDir
      monitorCfg.keepAwakeUnit
      "${pkgs.coreutils}/bin/date"
      "${pkgs.gawk}/bin/awk"
      "${pkgs.systemd}/bin/journalctl"
      "${pkgs.gnugrep}/bin/grep"
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
                Each attempt probes with ddcutil --maxtries 1,1,1 and verifies
                VCP D6 reads back On (0x01).
              '';
            };

            resumeRetrySeconds = lib.mkOption {
              type = lib.types.float;
              default = 0.25;
              description = "Seconds between resume attempts when I2C is not ready yet.";
            };

            resumeRemoteWakeWaitSeconds = lib.mkOption {
              type = lib.types.float;
              default = 5.0;
              description = ''
                After turning the monitor on, seconds to poll for a remote wake
                signal (wake-proxy keep-awake lease or SSH accept). If remote
                wake is detected, the monitor is turned back off.
              '';
            };

            resumeOnLocalWakeOnly = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = ''
                After resume, turn the monitor on immediately, then turn it off
                again if a remote wake-proxy keep-awake signal appears within
                resumeRemoteWakeWaitSeconds. Physical wakes keep the panel on.
              '';
            };

            remoteWakeUser = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = "wakeproxy-keep-awake";
              example = "wakeproxy-keep-awake";
              description = ''
                SSH user whose Accepted publickey journal line indicates a
                wake-proxy keep-awake session. Set to null to disable this signal.
              '';
            };

            keepAwakeStateDir = lib.mkOption {
              type = lib.types.str;
              default = "/var/lib/wakeproxy-keep-awake";
              description = ''
                Directory where wake-proxy keep-awake writes .pid / .until lease files.
              '';
            };

            keepAwakeUnit = lib.mkOption {
              type = lib.types.str;
              default = "wakeproxy-keep-awake";
              description = "Basename of keep-awake lease files (<unit>.pid / <unit>.until).";
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

        # Run classify+DDC outside the blocking system-sleep hook so thaw is
        # not delayed and I2C retries can proceed in parallel with resume.
        systemd.services.monitor-power-resume = {
          description = "Turn monitor on after sleep; off if remote wake-proxy";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${monitorResume}/bin/monitor-resume";
          };
        };

        environment.etc."systemd/system-sleep/monitor-power" = {
          source = pkgs.writeShellScript "monitor-power-resume-hook" ''
            case "$1" in
              pre)
                ${pkgs.systemd}/bin/journalctl -k -b --show-cursor -n 0 --output=short-unix 2>/dev/null \
                  | ${pkgs.gawk}/bin/awk -F';' '/^-- cursor:/ { print $2; exit }' \
                  > /run/monitor-power-suspend-cursor || true
                ${pkgs.coreutils}/bin/date -Iseconds > /run/monitor-power-suspend-since || true
                ;;
              post)
                # Non-blocking: do not hold systemd-sleep / user.slice thaw.
                ${pkgs.systemd}/bin/systemctl start --no-block monitor-power-resume.service || true
                ;;
            esac
          '';
          mode = "0755";
        };
      })
    ]);
  };
}
