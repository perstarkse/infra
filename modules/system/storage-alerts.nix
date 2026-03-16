_: {
  config.flake.nixosModules.storage-alerts = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.storage-alerts;
    ntfyTopicUrl = "${lib.removeSuffix "/" cfg.ntfy.serverUrl}/${cfg.ntfy.topic}";
    ntfyTags = lib.concatStringsSep "," cfg.ntfy.tags;
    ntfyAuthHeader =
      if cfg.ntfy.tokenFile == null
      then ""
      else ''
        curl_args+=( -H "Authorization: Bearer $(<${cfg.ntfy.tokenFile})" )
      '';
    notifier = pkgs.writeShellScript "storage-alerts-notify" ''
      set -euo pipefail

      title="''${1:?title required}"
      message="''${2:?message required}"
      priority="''${3:-${cfg.ntfy.priority}}"
      tags="''${4:-${ntfyTags}}"

      curl_args=(
        -fsS
        --retry 2
        --retry-delay 2
        -H "Title: $title"
        -H "Priority: $priority"
        -H "Tags: $tags"
      )

      ${ntfyAuthHeader}

      exec ${pkgs.curl}/bin/curl "''${curl_args[@]}" --data-binary "$message" ${lib.escapeShellArg ntfyTopicUrl}
    '';
    smartdNotifier = pkgs.writeShellScript "storage-alerts-smartd" ''
      set -euo pipefail

      device="''${SMARTD_DEVICESTRING:-''${SMARTD_DEVICE:-unknown device}}"
      title="${config.networking.hostName}: SMART alert on $device"
      message=$(cat <<EOF
      Host: ${config.networking.hostName}
      Device: $device
      Event: ''${SMARTD_FAILTYPE:-smartd}

      ''${SMARTD_MESSAGE:-}

      ''${SMARTD_FULLMESSAGE:-}
      EOF
      )

      exec ${notifier} "$title" "$message" high "${lib.concatStringsSep "," (cfg.ntfy.tags ++ ["smart"])}"
    '';
    mdadmNotifier = pkgs.writeShellScript "storage-alerts-mdadm" ''
      set -euo pipefail

      event="''${1:-mdadm event}"
      device="''${2:-unknown array}"
      detail=""
      if [ -e "$device" ]; then
        detail="$(${pkgs.mdadm}/bin/mdadm --detail "$device" 2>&1 || true)"
      fi

      message=$(cat <<EOF
      Host: ${config.networking.hostName}
      Event: $event
      Array: $device

      $detail
      EOF
      )

      exec ${notifier} "${config.networking.hostName}: mdadm $event" "$message" high "${lib.concatStringsSep "," (cfg.ntfy.tags ++ ["raid"])}"
    '';
    healthcheck = pkgs.writeShellScript "storage-alerts-healthcheck" ''
      set -euo pipefail

      state_dir=/var/lib/storage-alerts
      mkdir -p "$state_dir"

      sanitize() {
        printf '%s' "$1" | ${pkgs.coreutils}/bin/tr '/ :' '___'
      }

      mark_problem() {
        local key="$1"
        local title="$2"
        local message="$3"
        local state_file="$state_dir/$key"
        if [ ! -e "$state_file" ]; then
          ${notifier} "$title" "$message" high
          : > "$state_file"
        fi
      }

      clear_problem() {
        local key="$1"
        local title="$2"
        local message="$3"
        local state_file="$state_dir/$key"
        if [ -e "$state_file" ]; then
          ${notifier} "$title" "$message" default "${lib.concatStringsSep "," (cfg.ntfy.tags ++ ["white_check_mark"])}"
          rm -f "$state_file"
        fi
      }

      ${lib.concatMapStringsSep "\n" (mountPoint: ''
          if ${pkgs.util-linux}/bin/mountpoint -q ${lib.escapeShellArg mountPoint}; then
            clear_problem "mount-$(sanitize ${lib.escapeShellArg mountPoint})" "${config.networking.hostName}: mount recovered" "Mount ${mountPoint} is available again on ${config.networking.hostName}."
          else
            mark_problem "mount-$(sanitize ${lib.escapeShellArg mountPoint})" "${config.networking.hostName}: mount missing" "Mount ${mountPoint} is not available on ${config.networking.hostName}."
          fi
        '')
        cfg.mounts}

      shopt -s nullglob
      for md_path in /sys/block/md*/md; do
        array_name=$(basename "$(dirname "$md_path")")
        device="/dev/$array_name"
        key="mdadm-$(sanitize "$array_name")"
        degraded=$(cat "$md_path/degraded" 2>/dev/null || printf '0')
        if [ "$degraded" != "0" ]; then
          detail="$(${pkgs.mdadm}/bin/mdadm --detail "$device" 2>&1 || true)"
          mark_problem "$key" "${config.networking.hostName}: mdadm degraded" "Array $device is degraded on ${config.networking.hostName}.\n\n$detail"
        else
          clear_problem "$key" "${config.networking.hostName}: mdadm recovered" "Array $device is healthy again on ${config.networking.hostName}."
        fi
      done
    '';
  in {
    options.my.storage-alerts = {
      enable = lib.mkEnableOption "storage health alerts via ntfy";

      mounts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Mount points that must remain available.";
      };

      checkSchedule = lib.mkOption {
        type = lib.types.str;
        default = "*:0/10";
        description = "systemd OnCalendar schedule for storage health checks.";
      };

      smartd = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable SMART monitoring alerts.";
        };

        autodetect = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Autodetect SMART-capable devices.";
        };

        deviceOptions = lib.mkOption {
          type = lib.types.str;
          default = "-a";
          description = "Base smartd monitoring options for devices.";
        };
      };

      mdadm = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable mdadm event notifications.";
        };
      };

      ntfy = {
        serverUrl = lib.mkOption {
          type = lib.types.str;
          default = "http://10.0.0.1:2586";
          description = "Base ntfy server URL used for publishing alerts.";
        };

        topic = lib.mkOption {
          type = lib.types.str;
          default = "storage-alerts";
          description = "ntfy topic used for storage alerts.";
        };

        priority = lib.mkOption {
          type = lib.types.str;
          default = "default";
          description = "Default ntfy priority for recurring health checks.";
        };

        tags = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = ["warning" "floppy_disk"];
          description = "Default ntfy tags to attach to storage alerts.";
        };

        tokenFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Optional file containing an ntfy bearer token.";
        };
      };
    };

    config = lib.mkIf cfg.enable (lib.mkMerge [
      {
        systemd.services.storage-alerts-healthcheck = {
          description = "Storage health checks with ntfy alerts";
          after = ["network-online.target"];
          wants = ["network-online.target"];
          serviceConfig = {
            Type = "oneshot";
            StateDirectory = "storage-alerts";
            ExecStart = healthcheck;
          };
        };

        systemd.timers.storage-alerts-healthcheck = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = cfg.checkSchedule;
            Persistent = true;
          };
        };
      }

      (lib.mkIf cfg.smartd.enable {
        services.smartd = {
          enable = true;
          inherit (cfg.smartd) autodetect;
          defaults.monitored = "${cfg.smartd.deviceOptions} -m <nomailer> -M exec ${smartdNotifier}";
          defaults.autodetected = "${cfg.smartd.deviceOptions} -m <nomailer> -M exec ${smartdNotifier}";
        };
      })

      (lib.mkIf cfg.mdadm.enable {
        boot.swraid.mdadmConf = lib.mkAfter ''
          PROGRAM ${mdadmNotifier}
        '';
      })
    ]);
  };
}
