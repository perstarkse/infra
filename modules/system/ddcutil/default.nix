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

    substituteScript = name: scriptPath:
      pkgs.writeShellScriptBin name
      (lib.replaceStrings
        ["@MONITOR_DIR@" "@DISPLAY_NUM@" "@YQ@"]
        ["${monitorDataPackage}" (toString monitorCfg.display) "${pkgs.yq-go}/bin/yq"]
        (builtins.readFile scriptPath));
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
            enable = lib.mkEnableOption "monitor-profile command for DDC/CI picture modes";

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
          pkgs.yq-go
        ];
      })
    ]);
  };
}
