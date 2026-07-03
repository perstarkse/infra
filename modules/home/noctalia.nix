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
    noctaliaLauncher = pkgs.writeShellScriptBin "noctalia-shell-session" ''
      exec ${lib.getExe noctaliaPkg} "$@"
    '';
  in {
    imports = [inputs.noctalia.homeModules.default];

    options.my.noctalia = {
      enable = lib.mkEnableOption "Noctalia desktop shell";
    };

    config = lib.mkIf cfg.enable {
      programs.noctalia = {
        enable = true;
        package = noctaliaPkg;
        # v5 schema (TOML). Only non-default customizations are listed; the
        # rest align with v5 defaults (dark theme, no telemetry, 24h clock,
        # dock/nightlight/idle disabled, solid bar). Validated at build time
        # via `noctalia config validate` (validateConfig defaults to true).
        settings = {
          shell = {
            # v4 radiusRatio = 0 -> square corners.
            corner_radius_scale = 0.0;
            panel = {
              # v4 showOutline = false, enableShadows = false.
              borders = false;
              shadow = false;
              # v4 controlCenter.position = "close_to_bar_button".
              open_near_click_control_center = true;
            };
          };
          wallpaper = {
            enabled = false;
            fill_color = "#000000";
          };
          weather.enabled = true;
          location.auto_locate = true;

          bar.main = {
            # v4 frameRadius = 0, marginVertical/Horizontal = 0, enableShadows = false.
            radius = 0;
            margin_h = 0;
            margin_v = 0;
            shadow = false;
            # v4 bar.widgets.left/center/right -> v5 start/center/end.
            # Widget type names: "sysmon" (defaults cpu_usage), "active_window",
            # "media" (compact via album_art_only below), "workspaces", "tray",
            # "notifications", "battery", "volume", "control-center", "clock".
            start = ["sysmon" "active_window" "media"];
            center = ["workspaces"];
            end = ["tray" "notifications" "battery" "volume" "control-center" "clock"];
          };

          widget = {
            # v4 MediaMini -> compact album-art-only media widget.
            media.album_art_only = true;
            # v4 Workspace.labelMode = "none".
            workspaces.display = "none";
            # v4 Battery.alwaysShowPercentage = false.
            battery.show_label = false;
          };

          # v4 controlCenter.shortcuts.left/right -> single ordered list (max 6).
          # "KeepAwake" maps to the v5 "caffeine" shortcut (idle inhibitor).
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

      my.niri.extraSpawnAtStartup = [["noctalia-shell-session"]];

      home.activation.restartNoctaliaShell = lib.hm.dag.entryAfter ["writeBoundary"] ''
        if ${pkgs.procps}/bin/pgrep -x noctalia >/dev/null; then
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/killall noctalia 2>/dev/null || true
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/sleep 0.5
        fi
        if ! ${pkgs.procps}/bin/pgrep -x noctalia >/dev/null; then
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
