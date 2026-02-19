{
  config.flake.nixosModules.auto-suspend = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.autoSuspend;

    autoSuspendScript = pkgs.writeShellScript "auto-suspend-check" ''
      set -euo pipefail

      IDLE_FILE="/run/auto-suspend/idle-count"
      REQUIRED_CHECKS=${toString cfg.requiredIdleChecks}
      LOAD_THRESHOLD="${cfg.loadThreshold}"
      USER_IDLE_SECONDS=${toString cfg.userIdleSeconds}

      mkdir -p /run/auto-suspend

      # Get 5-minute load average
      loadavg=$(${pkgs.coreutils}/bin/cut -d' ' -f2 /proc/loadavg)

      # Check if load is below threshold
      load_idle=$(${pkgs.gawk}/bin/awk -v avg="$loadavg" -v threshold="$LOAD_THRESHOLD" \
        'BEGIN { print (avg < threshold) ? "1" : "0" }')

      # Check for user input activity via logind IdleHint (set by swayidle)
      # Only check graphical sessions (wayland/x11), ignore TTY/pts sessions
      user_idle=1
      for session in $(${pkgs.systemd}/bin/loginctl list-sessions --no-legend | ${pkgs.gawk}/bin/awk '{print $1}'); do
        session_type=$(${pkgs.systemd}/bin/loginctl show-session "$session" -p Type --value 2>/dev/null || echo "")
        if [ "$session_type" = "wayland" ] || [ "$session_type" = "x11" ]; then
          idle_hint=$(${pkgs.systemd}/bin/loginctl show-session "$session" -p IdleHint --value 2>/dev/null || echo "yes")
          if [ "$idle_hint" = "no" ]; then
            user_idle=0
            break
          fi
        fi
      done

      # Check for inhibitors - only care about "sleep" with "block" mode
      inhibited=0
      ${lib.optionalString cfg.checkInhibitors ''
        if ${pkgs.systemd}/bin/systemd-inhibit --list --no-legend | grep -E 'sleep.*block' | grep -qv 'handle-power-key'; then
          inhibited=1
        fi
      ''}

      # Build status string
      status=""
      [ "$load_idle" = "0" ] && status="$status load:ACTIVE($loadavg)"
      [ "$load_idle" = "1" ] && status="$status load:idle($loadavg)"
      [ "$user_idle" = "0" ] && status="$status user:ACTIVE"
      [ "$user_idle" = "1" ] && status="$status user:idle"
      [ "$inhibited" = "1" ] && status="$status inhibitor:BLOCKING"

      current=$(cat "$IDLE_FILE" 2>/dev/null || echo "0")

      # Determine if system is idle
      if [ "$load_idle" = "1" ] && [ "$user_idle" = "1" ] && [ "$inhibited" = "0" ]; then
        new=$((current + 1))
        echo "$new" > "$IDLE_FILE"
        echo "$(date): IDLE $new/$REQUIRED_CHECKS —$status" >> /var/log/auto-suspend.log

        if [ "$new" -ge "$REQUIRED_CHECKS" ]; then
          echo "$(date): SUSPENDING after $new consecutive idle checks" >> /var/log/auto-suspend.log
          echo "0" > "$IDLE_FILE"
          ${pkgs.systemd}/bin/systemctl suspend
        fi
      else
        echo "$(date): ACTIVE (reset from $current/$REQUIRED_CHECKS) —$status" >> /var/log/auto-suspend.log
        echo "0" > "$IDLE_FILE"
      fi
    '';
  in {
    options.my.autoSuspend = {
      enable = lib.mkEnableOption "automatic suspend on idle";

      checkIntervalMinutes = lib.mkOption {
        type = lib.types.int;
        default = 10;
        description = "How often to check for idle state (minutes)";
      };

      requiredIdleChecks = lib.mkOption {
        type = lib.types.int;
        default = 3;
        description = "Number of consecutive idle checks before suspend";
      };

      loadThreshold = lib.mkOption {
        type = lib.types.str;
        default = "1.0";
        description = "5-min load average threshold (below = idle). For 5950x, 1.0 is very low.";
      };

      userIdleSeconds = lib.mkOption {
        type = lib.types.int;
        default = 600;
        description = "Seconds of no user input before considering user idle";
      };

      checkInhibitors = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Respect systemd inhibitors (audio, downloads, etc.)";
      };
    };

    config = lib.mkIf cfg.enable {
      systemd = {
        # Timer runs the check periodically
        timers.auto-suspend = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnBootSec = "${toString cfg.checkIntervalMinutes}min";
            OnUnitActiveSec = "${toString cfg.checkIntervalMinutes}min";
            Persistent = false;
          };
        };

        services.auto-suspend = {
          description = "Check for idle and suspend";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = autoSuspendScript;
          };
        };

        # Reset idle counter on resume
        services.auto-suspend-reset = {
          description = "Reset auto-suspend counter on wake";
          wantedBy = ["suspend.target" "hibernate.target"];
          after = ["suspend.target" "hibernate.target"];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.coreutils}/bin/rm -f /run/auto-suspend/idle-count";
          };
        };
      };
    };
  };
}
