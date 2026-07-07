{
  config.flake.nixosModules.ddcutil = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.ddcutil;
    monitorCfg = cfg.monitor;

    monitorDataPackage =
      if monitorCfg.enable
      then
        pkgs.runCommand "ddcutil-monitor-data" {} ''
          mkdir -p $out
          cp -r ${monitorCfg.dataDir}/. $out/
        ''
      else null;

    scriptSubstitutions = [
      "@MONITOR_DIR@"
      "@DISPLAY_NUM@"
      "@YQ@"
      "@DDCUTIL@"
      "@SLEEP@"
      "@LOGGER@"
      "@SEQ@"
      "@MAX_ATTEMPTS@"
      "@RETRY_INTERVAL@"
    ];

    scriptReplacements = [
      "${monitorDataPackage}"
      (toString monitorCfg.display)
      "${pkgs.yq-go}/bin/yq"
      "${pkgs.ddcutil}/bin/ddcutil"
      "${pkgs.coreutils}/bin/sleep"
      "${pkgs.util-linux}/bin/logger"
      "${pkgs.coreutils}/bin/seq"
      (toString monitorCfg.resumeMaxAttempts)
      (toString monitorCfg.resumeRetrySeconds)
    ];

    substituteScript = name: scriptPath:
      pkgs.writeShellScriptBin name
      (lib.replaceStrings scriptSubstitutions scriptReplacements (builtins.readFile scriptPath));

    monitorPower = substituteScript "monitor-power" ./scripts/power.sh;
    monitorResume = substituteScript "monitor-resume" ./scripts/resume.sh;

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
          [pkgs.ddcutil]
          ++ lib.optional cfg.ddcui pkgs.ddcui;
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
