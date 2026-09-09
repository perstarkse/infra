_: {
  config.flake.nixosModules.backup-mx = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.backupMx;
    queueWatchScript = pkgs.writeShellScript "backup-mx-queue-watch" ''
      set -euo pipefail

      state_dir=/var/lib/backup-mx-queue
      mkdir -p "$state_dir"

      send_alert() {
        local subject="$1"
        local body="$2"
        ${lib.optionalString (cfg.queueWatch.smtpEnvFile != null) ''
        set -a
        # shellcheck disable=SC1090
        . ${cfg.queueWatch.smtpEnvFile}
        set +a
        rcpts=()
        IFS=',' read -ra _rcpts <<< "''${GATUS_ALERT_EMAIL_TO:?GATUS_ALERT_EMAIL_TO not set}"
        for r in "''${_rcpts[@]}"; do rcpts+=(--mail-rcpt "$r"); done
        {
          printf 'From: %s\r\nTo: %s\r\nSubject: [backup-mx] %s\r\n\r\n' "''${GATUS_SMTP_FROM:?}" "''${GATUS_ALERT_EMAIL_TO:?}" "$subject"
          printf '%s\r\n' "$body"
        } | ${pkgs.curl}/bin/curl -fsS --max-time 30 \
          "smtp://''${GATUS_SMTP_HOST:?}:587" --ssl-reqd \
          --mail-from "''${GATUS_SMTP_FROM:?}" "''${rcpts[@]}" \
          --user "''${GATUS_SMTP_USERNAME:?}:''${GATUS_SMTP_PASSWORD:?}" -T -
      ''}
        ${lib.optionalString (cfg.queueWatch.smtpEnvFile == null) ''
        echo "(no smtpEnvFile configured: alert [$subject] visible via failed unit only)" >&2
      ''}
      }

      now=$(date +%s)
      depth=0
      oldest=0

      queue_json="$(mktemp)"
      trap 'rm -f "$queue_json"' EXIT
      ${pkgs.postfix}/bin/postqueue -j > "$queue_json" 2>/dev/null || true
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        arrival=$(printf '%s' "$line" | ${pkgs.jq}/bin/jq -r '.arrival_time // empty' 2>/dev/null || true)
        [ -z "$arrival" ] && continue
        depth=$((depth + 1))
        if [ "$oldest" = "0" ] || [ "$arrival" -lt "$oldest" ]; then
          oldest=$arrival
        fi
      done < "$queue_json"

      if [ "$oldest" = "0" ]; then
        age_hours=0
      else
        age_hours=$(( (now - oldest) / 3600 ))
      fi

      breached=""
      if [ "$depth" -gt ${toString cfg.queueWatch.maxDepth} ]; then
        breached="depth $depth > ${toString cfg.queueWatch.maxDepth}"
      fi
      if [ "$age_hours" -gt ${toString cfg.queueWatch.maxAgeHours} ]; then
        breached="''${breached:+$breached, }oldest age ''${age_hours}h > ${toString cfg.queueWatch.maxAgeHours}h"
      fi

      if [ -z "$breached" ]; then
        if [ -e "$state_dir/alert-sent" ]; then
          send_alert "recovered" "Backup MX queue on ${config.networking.hostName} recovered (depth $depth, oldest ''${age_hours}h)."
          rm -f "$state_dir/alert-sent"
        fi
        echo "Backup MX queue OK (depth $depth, oldest ''${age_hours}h)."
        exit 0
      fi

      echo "Backup MX queue breached: $breached" >&2
      if [ ! -e "$state_dir/alert-sent" ]; then
        send_alert "queue breached" "Backup MX queue on ${config.networking.hostName} breached: $breached (depth $depth, oldest ''${age_hours}h)."
        : > "$state_dir/alert-sent"
      fi
      exit 1
    '';
  in {
    options.my.backupMx = {
      enable = lib.mkEnableOption "queue-only backup MX (accepts mail for relay domains, forwards to the primary)";

      primaryHost = lib.mkOption {
        type = lib.types.str;
        default = "mail.stark.pub";
        description = "Hostname of the primary mail server that queued mail is forwarded to.";
      };

      primaryPort = lib.mkOption {
        type = lib.types.port;
        default = 25;
        description = "SMTP port on the primary mail server.";
      };

      relayDomains = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["stark.pub"];
        description = "Domains this backup accepts mail for and forwards to the primary. mydestination stays empty so nothing is delivered locally.";
      };

      listenPort = lib.mkOption {
        type = lib.types.port;
        default = 25;
        description = "Port the backup MX listens on.";
      };

      queueWatch = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Watch queue depth/age and alert before mail starts bouncing.";
        };

        maxDepth = lib.mkOption {
          type = lib.types.int;
          default = 100;
          description = "Alert when more than this many messages are queued.";
        };

        maxAgeHours = lib.mkOption {
          type = lib.types.int;
          default = 72;
          description = "Alert when the oldest queued message is older than this many hours (well inside the 30d queue lifetime).";
        };

        checkSchedule = lib.mkOption {
          type = lib.types.str;
          default = "hourly";
          description = "systemd OnCalendar schedule for the queue watch.";
        };

        smtpEnvFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Environment file with GATUS_SMTP_HOST/_FROM/_USERNAME/_PASSWORD and GATUS_ALERT_EMAIL_TO (same shape as the gatus env secret) used to mail breach/recovery alerts via the external relayer. Without it the breach is only visible via the failed unit.";
        };
      };
    };

    config = lib.mkIf cfg.enable (lib.mkMerge [
      {
        services.postfix = {
          enable = true;
          settings.main = {
            # Queue-only backup: never deliver locally. mydestination must stay
            # empty so Postfix treats every accepted recipient as relayable and
            # forwards via relayhost. Setting mydestination = stark.pub here
            # would accept mail into a maildir that does not exist -> bounce.
            mydestination = "";
            relay_domains = cfg.relayDomains;
            relayhost = ["[${cfg.primaryHost}]:${toString cfg.primaryPort}"];
            inet_interfaces = "all";
            inet_protocols = "ipv4";
            # Open-relay guard lives here (NOT in smtpd_client_restrictions,
            # which would reject the external senders a backup MX must accept):
            # allow relaying only to the configured relay domains, from anyone.
            smtpd_relay_restrictions = ["reject_unauth_destination"];
            # Belt and braces: permit loopback injection, reject foreign
            # destinations. Rejects only destinations outside relay_domains.
            smtpd_recipient_restrictions = [
              "permit_mynetworks"
              "reject_unauth_destination"
            ];
            # Opportunistic STARTTLS to the primary (matches the primary's
            # smtpd_tls_security_level = "may"); falls back to plaintext on a
            # failed handshake/verification, so no cert is needed on the backup.
            smtp_tls_security_level = "may";
            smtp_dns_support_level = "dnssec";
            # Hold queued mail 30d instead of the 5d default: the backup MX
            # exists to outlast extended outages (travel, hardware RMA).
            # backup-mx-queue-watch alerts long before this expires
            # (defaults: depth > 100 or oldest age > 72h).
            maximal_queue_lifetime = "30d";
            bounce_queue_lifetime = "30d";
          };
        };

        networking.firewall.allowedTCPPorts = [cfg.listenPort];

        assertions = [
          {
            assertion = cfg.relayDomains != [];
            message = "backupMx.relayDomains must not be empty — a backup MX needs at least one relay domain.";
          }
        ];
      }
      (lib.mkIf cfg.queueWatch.enable {
        systemd.services.backup-mx-queue-watch = {
          description = "Backup MX queue depth/age watch (alerts before mail bounces)";
          after = ["postfix.service"];
          wants = ["postfix.service"];
          serviceConfig = {
            Type = "oneshot";
            StateDirectory = "backup-mx-queue";
            ExecStart = queueWatchScript;
          };
        };

        systemd.timers.backup-mx-queue-watch = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = cfg.queueWatch.checkSchedule;
            Persistent = true;
          };
        };
      })
    ]);
  };
}
