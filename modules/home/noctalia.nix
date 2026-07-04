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
    voxtypePluginsRoot = pkgs.runCommand "noctalia-voxtype-plugins" {} ''
      mkdir -p $out/voxtype-status
      cp ${./noctalia-plugins/voxtype-status/plugin.toml} $out/voxtype-status/plugin.toml
      cp ${./noctalia-plugins/voxtype-status/status.luau} $out/voxtype-status/status.luau
    '';
    voxtypePluginId = "infra/voxtype-status";
    voxtypeCmd =
      if lib.hasAttrByPath ["programs" "voxtype" "package"] config
      then lib.getExe config.programs.voxtype.package
      else lib.getExe inputs.voxtype.packages.${system}.default;
    systemctlCmd = "${pkgs.systemd}/bin/systemctl";
  in {
    imports = [inputs.noctalia.homeModules.default];

    options.my.noctalia = {
      enable = lib.mkEnableOption "Noctalia desktop shell";
    };

    config = lib.mkIf cfg.enable {
      stylix.targets.noctalia.enable = true;
      stylix.enableReleaseChecks = false;

      programs.noctalia = {
        enable = true;
        package = noctaliaPkg;
        settings = {
          shell = {
            corner_radius_scale = 0.0;
            niri_overview_type_to_launch_enabled = true;
            panel = {
              borders = false;
              shadow = false;
              open_near_click_control_center = true;
            };
          };
          wallpaper = {
            enabled = false;
            fill_color = "#000000";
          };
          weather.enabled = true;
          location.auto_locate = true;

          brightness = {
            enable_ddcutil = true;
            monitor."DP-2".backend = "ddcutil";
          };

          bar.main = {
            radius = 0;
            margin_edge = 0;
            margin_ends = 0;
            margin_opposite_edge = 0;
            shadow = false;
            thickness = 24;
            padding = 8;
            scale = 0.9;
            widget_spacing = 4;
            start = ["sysmon" "active_window" "media"];
            center = ["workspaces"];
            end = ["tray" "notifications" "battery" "volume" "brightness" "control-center" "voxtype-status" "clock"];
          };

          plugins = {
            enabled = [voxtypePluginId];
            source = [
              {
                name = "voxtype";
                kind = "path";
                location = toString voxtypePluginsRoot;
              }
            ];
          };

          widget = {
            media.album_art_only = true;
            workspaces.display = "none";
            battery.show_label = false;
            voxtype-status = {
              type = "${voxtypePluginId}:status";
              voxtype_cmd = voxtypeCmd;
              systemctl_cmd = systemctlCmd;
            };
          };

          control_center.shortcuts = [
            {type = "bluetooth";}
            {type = "wallpaper";}
            {type = "notification";}
            {type = "power_profile";}
            {type = "caffeine";}
            {type = "nightlight";}
          ];
        };
      };

      my.niri.extraSpawnAtStartup = [["noctalia"]];

      home.activation.restartNoctaliaShell = lib.hm.dag.entryAfter ["writeBoundary"] ''
        if ${pkgs.procps}/bin/pgrep -x noctalia >/dev/null; then
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/killall noctalia 2>/dev/null || true
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/sleep 0.5
        fi
        if ! ${pkgs.procps}/bin/pgrep -x noctalia >/dev/null; then
          $DRY_RUN_CMD ${lib.getExe noctaliaPkg} >/dev/null 2>&1 &
        fi
      '';

      home.packages = with pkgs; [
        libsForQt5.qt5.qtwayland
        qt6.qtwayland
      ];
    };
  };
}
