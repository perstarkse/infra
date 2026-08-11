{
  config.flake.nixosModules.auto-suspend = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.auto-suspend;
    useSystemSuspend =
      cfg.useSystemSuspend
      && config.my.ddcutil.enable
      && config.my.ddcutil.monitor.enable;

    suspendCommand =
      if useSystemSuspend
      then ''
        if command -v system-suspend >/dev/null 2>&1; then
          system-suspend
        else
          ${pkgs.systemd}/bin/systemctl suspend
        fi
      ''
      else ''
        ${pkgs.systemd}/bin/systemctl suspend
      '';

    # Records the CLOCK_MONOTONIC usec timestamp of the last evdev input event.
    # evdev is the ground truth for "is someone using this machine": physical
    # keyboards/mice and uinput virtual devices (Sunshine, Steam Remote Play)
    # all land here, and Wayland idle-inhibit cannot suppress it.
    inputWatchScript = pkgs.writeScript "auto-suspend-input-watch" ''
      #!${pkgs.python3}/bin/python3
      import glob
      import os
      import select
      import time

      STATE_DIR = "/run/auto-suspend"
      STATE_FILE = os.path.join(STATE_DIR, "last-input")

      def now_us():
          return int(time.clock_gettime(time.CLOCK_MONOTONIC) * 1_000_000)

      def write_state():
          os.makedirs(STATE_DIR, exist_ok=True)
          tmp = STATE_FILE + ".tmp"
          with open(tmp, "w") as fh:
              fh.write(str(now_us()))
          os.replace(tmp, STATE_FILE)

      # Baseline at startup: no input yet, so the machine counts as idle from
      # boot until the first evdev event.
      write_state()

      devices = {}  # file object -> device path

      while True:
          present = [
              p for p in glob.glob("/dev/input/event*") if os.access(p, os.R_OK)
          ]
          for p in present:
              if p not in devices.values():
                  try:
                      fh = open(p, "rb")
                      os.set_blocking(fh.fileno(), False)
                      devices[fh] = p
                  except OSError:
                      pass
          for fh in list(devices):
              if devices[fh] not in present:
                  try:
                      fh.close()
                  except OSError:
                      pass
                  del devices[fh]

          readable, _, _ = select.select(list(devices), [], [], 1.0)
          if readable:
              # Any evdev event is input activity. Drain without grabbing so
              # the compositor keeps receiving the same events.
              for fh in readable:
                  try:
                      fh.read(65536)
                  except OSError:
                      pass
              write_state()
    '';

    resetScript = pkgs.writeShellScript "auto-suspend-reset" ''
      ${pkgs.coreutils}/bin/rm -f /run/auto-suspend/idle-count
      # Re-baseline last-input at wake; otherwise the pre-suspend timestamp
      # makes the first check after resume instantly idle.
      ${pkgs.systemd}/bin/systemctl restart auto-suspend-input-watch.service
    '';

    autoSuspendScript = pkgs.writeShellScript "auto-suspend-check" ''
      set -euo pipefail

      IDLE_FILE="/run/auto-suspend/idle-count"
      LAST_INPUT_FILE="/run/auto-suspend/last-input"
      REQUIRED_CHECKS=${toString cfg.requiredIdleChecks}
      LOAD_THRESHOLD="${cfg.loadThreshold}"
      USER_IDLE_SECONDS=${toString cfg.userIdleSeconds}
      ACTIVE_TCP_PORTS="${lib.concatStringsSep " " (map toString cfg.activeTcpPorts)}"

      mkdir -p /run/auto-suspend

      # Get 5-minute load average
      loadavg=$(${pkgs.coreutils}/bin/cut -d' ' -f2 /proc/loadavg)

      # Check if load is below threshold
      load_idle=$(${pkgs.gawk}/bin/awk -v avg="$loadavg" -v threshold="$LOAD_THRESHOLD" \
        'BEGIN { print (avg < threshold) ? "1" : "0" }')

      # User activity = real input events, tracked by auto-suspend-input-watch
      # from /dev/input. logind's session IdleHint cannot be used here: swayidle
      # is its only writer, and Wayland idle-inhibit (Electron apps, video
      # players) suppresses the idle flip, so the hint stays "no" both while
      # someone types for hours and while nobody is at the seat.
      user_idle=1
      user_idle_seconds=""
      if [ -r "$LAST_INPUT_FILE" ] && [ -s "$LAST_INPUT_FILE" ]; then
        last_input_us=$(${pkgs.coreutils}/bin/cat "$LAST_INPUT_FILE")
        now_monotonic_us=$(${pkgs.python3}/bin/python3 -c 'import time; print(int(time.clock_gettime(time.CLOCK_MONOTONIC) * 1_000_000))')
        if [ -n "$last_input_us" ] && [ "$last_input_us" -le "$now_monotonic_us" ]; then
          user_idle_seconds="$(( (now_monotonic_us - last_input_us) / 1000000 ))"
          if [ "$user_idle_seconds" -lt "$USER_IDLE_SECONDS" ]; then
            user_idle=0
          fi
        fi
      fi

      # Check for inhibitors - only care about "sleep" with "block" mode
      inhibited=0
      ${lib.optionalString cfg.checkInhibitors ''
        if ${pkgs.systemd}/bin/systemd-inhibit --list --no-legend | grep -E 'sleep.*block' | grep -qv 'handle-power-key'; then
          inhibited=1
        fi
      ''}

      # Check for established TCP connections on configured ports (remote sessions)
      tcp_active=0
      if [ -n "$ACTIVE_TCP_PORTS" ]; then
        for port in $ACTIVE_TCP_PORTS; do
          if ${pkgs.iproute2}/bin/ss -Htan state established "( sport = :$port )" | ${pkgs.gawk}/bin/awk 'NF { found=1 } END { exit(found ? 0 : 1) }'; then
            tcp_active=1
            break
          fi
        done
      fi

      # Build status string
      status=""
      [ "$load_idle" = "0" ] && status="$status load:ACTIVE($loadavg)"
      [ "$load_idle" = "1" ] && status="$status load:idle($loadavg)"
      if [ "$user_idle" = "0" ]; then
        status="$status user:ACTIVE(idleFor=''${user_idle_seconds}s)"
      elif [ -n "$user_idle_seconds" ]; then
        status="$status user:idle(idleFor=''${user_idle_seconds}s)"
      else
        status="$status user:idle(no-input-signal)"
      fi
      [ "$inhibited" = "1" ] && status="$status inhibitor:BLOCKING"
      [ "$tcp_active" = "1" ] && status="$status tcp:ACTIVE"
      [ "$tcp_active" = "0" ] && [ -n "$ACTIVE_TCP_PORTS" ] && status="$status tcp:idle"

      current=$(cat "$IDLE_FILE" 2>/dev/null || echo "0")

      # Determine if system is idle
      if [ "$load_idle" = "1" ] && [ "$user_idle" = "1" ] && [ "$inhibited" = "0" ] && [ "$tcp_active" = "0" ]; then
        new=$((current + 1))
        echo "$new" > "$IDLE_FILE"
        echo "$(date): IDLE $new/$REQUIRED_CHECKS —$status" >> /var/log/auto-suspend.log

        if [ "$new" -ge "$REQUIRED_CHECKS" ]; then
          echo "$(date): SUSPENDING after $new consecutive idle checks" >> /var/log/auto-suspend.log
          echo "0" > "$IDLE_FILE"
          ${suspendCommand}
        fi
      else
        echo "$(date): ACTIVE (reset from $current/$REQUIRED_CHECKS) —$status" >> /var/log/auto-suspend.log
        echo "0" > "$IDLE_FILE"
      fi
    '';
  in {
    options.my.auto-suspend = {
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
        description = "Seconds without input (evdev events) before considering the machine idle";
      };

      checkInhibitors = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Respect systemd inhibitors (audio, downloads, etc.)";
      };

      activeTcpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [];
        example = [9898 22];
        description = "Treat system as active when established TCP connections exist on these local ports (useful for remote dev sessions).";
      };

      useSystemSuspend = lib.mkOption {
        type = lib.types.bool;
        default = config.my.ddcutil.monitor.enable;
        description = ''
          Suspend via system-suspend when available so DDC monitor power-off runs first.
          Requires my.ddcutil.monitor to be enabled.
        '';
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

        # Records last input time; the check below reads /run/auto-suspend/last-input.
        services.auto-suspend-input-watch = {
          description = "Track last input event time for auto-suspend";
          wantedBy = ["multi-user.target"];
          serviceConfig = {
            Type = "simple";
            ExecStart = inputWatchScript;
            Restart = "always";
            RestartSec = "1s";
          };
        };

        services.auto-suspend = {
          description = "Check for idle and suspend";
          after = ["auto-suspend-input-watch.service"];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = autoSuspendScript;
          };
        };

        # Reset idle counter and re-baseline input tracking on resume
        services.auto-suspend-reset = {
          description = "Reset auto-suspend counters on wake";
          wantedBy = ["suspend.target" "hibernate.target"];
          after = ["suspend.target" "hibernate.target"];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = resetScript;
          };
        };
      };
    };
  };
}
