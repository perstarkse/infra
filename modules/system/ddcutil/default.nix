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
      "@MKDIR@"
      "@DIRNAME@"
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
      "${pkgs.coreutils}/bin/mkdir"
      "${pkgs.coreutils}/bin/dirname"
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

    monitorPowerInput =
      pkgs.writeScript "monitor-power-input"
      (lib.replaceStrings
        ["#!/usr/bin/env python3" "@MONITOR_POWER@"]
        ["#!${pkgs.python3}/bin/python3" "${monitorPower}/bin/monitor-power"]
        (builtins.readFile ./scripts/physical-input.py));

    systemSuspend =
      pkgs.writeShellScriptBin "system-suspend" (builtins.readFile ./scripts/suspend.sh);

    keepAwakeUntilFile = "${monitorCfg.keepAwakeStateDir}/${monitorCfg.keepAwakeUnit}.until";
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
                Resume attempts to force the monitor off after system sleep.
                Each attempt probes with ddcutil --maxtries 1,1,1 and verifies
                VCP D6 reads back Off (0x05). Physical input can abort this
                and turn the panel on instead.
              '';
            };

            resumeRetrySeconds = lib.mkOption {
              type = lib.types.float;
              default = 0.25;
              description = "Seconds between resume attempts when I2C is not ready yet.";
            };

            keepAwakeStateDir = lib.mkOption {
              type = lib.types.str;
              default = "/var/lib/wakeproxy-keep-awake";
              description = ''
                Directory where wake-proxy keep-awake writes .pid / .until lease files.
                A new lease forces the monitor off (remote WoL session).
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

        systemd.services.monitor-power-input = {
          description = "Turn monitor on from physical seat input";
          wantedBy = ["multi-user.target"];
          after = ["systemd-udevd.service"];
          serviceConfig = {
            Type = "simple";
            Restart = "always";
            RestartSec = 1;
            ExecStart = "${monitorPowerInput}";
          };
        };

        # Force DDC off after thaw so HDMI/GPU resume cannot leave the panel
        # lit. Physical input (monitor-power-input) turns it back on.
        systemd.services.monitor-power-resume = {
          description = "Force monitor off after sleep until physical input";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${monitorResume}/bin/monitor-resume";
          };
        };

        systemd.paths.monitor-power-keep-awake-off = {
          description = "Watch wake-proxy keep-awake lease for remote WoL";
          wantedBy = ["multi-user.target"];
          pathConfig.PathModified = keepAwakeUntilFile;
        };

        systemd.services.monitor-power-keep-awake-off = {
          description = "Force monitor off when wake-proxy keep-awake starts";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${monitorResume}/bin/monitor-resume keep-awake";
          };
        };

        environment.etc."systemd/system-sleep/monitor-power" = {
          source = pkgs.writeShellScript "monitor-power-resume-hook" ''
            case "$1" in
              pre)
                ${pkgs.coreutils}/bin/mkdir -p /run/monitor-power
                ${pkgs.coreutils}/bin/printf 'off-until-input\n' > /run/monitor-power/policy
                ;;
              post)
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
