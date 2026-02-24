_: {
  config.flake.nixosModules.heartbeat = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.heartbeat;
    envFile = config.my.secrets.getPath cfg.secretName cfg.secretFile;
    receiverAlert = cfg.receiver.deadmanAlert;
    receiverEndpointApiId =
      if cfg.receiver.externalEndpointApiId == null
      then "${cfg.receiver.deadmanGroup}_${cfg.receiver.externalEndpointName}"
      else cfg.receiver.externalEndpointApiId;

    endpointPath =
      if lib.hasPrefix "/" cfg.receiver.path
      then cfg.receiver.path
      else "/${cfg.receiver.path}";

    receiverScript = pkgs.writeText "heartbeat-receiver.py" ''
      import http.server
      import hmac
      import os
      import socket
      import urllib.parse
      import urllib.request

      LISTEN = ("${cfg.receiver.listenAddress}", ${toString cfg.receiver.port})
      EXPECTED_PATH = "${endpointPath}"
      PUSH_TOKEN = os.environ["HEARTBEAT_PUSH_TOKEN"]
      GATUS_URL = "http://127.0.0.1:${toString cfg.receiver.gatusPort}/api/v1/endpoints/${receiverEndpointApiId}/external?success=true&duration=1ms"


      class Handler(http.server.BaseHTTPRequestHandler):
          def do_GET(self):
              self.send_response(405)
              self.end_headers()

          def do_POST(self):
              self._handle()

          def log_message(self, fmt, *args):
              return

          def _handle(self):
              parsed = urllib.parse.urlparse(self.path)
              if parsed.path != EXPECTED_PATH:
                  self.send_response(404)
                  self.end_headers()
                  return

              auth = self.headers.get("Authorization", "")
              prefix = "Bearer "
              token = auth[len(prefix):].strip() if auth.startswith(prefix) else ""
              if not hmac.compare_digest(token, PUSH_TOKEN):
                  self.send_response(403)
                  self.end_headers()
                  return

              req = urllib.request.Request(
                  GATUS_URL,
                  method="POST",
                  headers={"Authorization": f"Bearer {PUSH_TOKEN}"},
              )
              try:
                  with urllib.request.urlopen(req, timeout=${toString cfg.receiver.gatusTimeoutSeconds}):
                      pass
              except Exception:
                  self.send_response(502)
                  self.end_headers()
                  return

              self.send_response(204)
              self.end_headers()


      class IPv6ThreadingHTTPServer(http.server.ThreadingHTTPServer):
          address_family = socket.AF_INET6


      Server = IPv6ThreadingHTTPServer if ":" in LISTEN[0] else http.server.ThreadingHTTPServer

      with Server(LISTEN, Handler) as httpd:
          httpd.serve_forever()
    '';

    pushScript = pkgs.writeShellScript "heartbeat-push" ''
      set -euo pipefail

      ${
        if cfg.push.endpointUrl == null
        then ''
          target_url="''${HEARTBEAT_URL:?HEARTBEAT_URL must be set when my.heartbeat.push.endpointUrl is null}"
        ''
        else ''
          target_url=${lib.escapeShellArg cfg.push.endpointUrl}
        ''
      }

      if [[ "$target_url" == *"change-me"* ]]; then
        echo "heartbeat-push: HEARTBEAT_URL still has placeholder value" >&2
        exit 64
      fi

      # Normalize bare IPv6 URLs like http://fdxx:...:18080/heartbeat into
      # bracketed form expected by curl: http://[fdxx:...]:18080/heartbeat.
      if [[ "$target_url" == http://* || "$target_url" == https://* ]]; then
        scheme="''${target_url%%://*}"
        rest="''${target_url#*://}"
        authority="$rest"
        suffix=""

        if [[ "$rest" == */* ]]; then
          authority="''${rest%%/*}"
          suffix="/''${rest#*/}"
        fi

        if [[ "$authority" != \[*\]* && "$authority" == *:*:* ]]; then
          host="$authority"
          port=""
          last_segment="''${authority##*:}"
          prefix="''${authority%:*}"

          if [[ "$last_segment" =~ ^[0-9]+$ && "$prefix" == *:* ]]; then
            host="$prefix"
            port=":$last_segment"
          fi

          authority="[$host]$port"
          target_url="''${scheme}://''${authority}''${suffix}"
        fi
      fi

      ${pkgs.curl}/bin/curl -fsS \
        --connect-timeout ${toString cfg.push.connectTimeoutSeconds} \
        --max-time ${toString cfg.push.requestTimeoutSeconds} \
        --retry ${toString cfg.push.retries} \
        --retry-delay ${toString cfg.push.retryDelaySeconds} \
        --retry-all-errors \
        -X POST \
        -H "Authorization: Bearer $HEARTBEAT_PUSH_TOKEN" \
        "$target_url" \
        >/dev/null
    '';
  in {
    options.my.heartbeat = {
      secretName = lib.mkOption {
        type = lib.types.str;
        default = "heartbeat";
        description = "Secret generator name that provides heartbeat environment variables.";
      };

      secretFile = lib.mkOption {
        type = lib.types.str;
        default = "env";
        description = "Secret file name used by heartbeat services.";
      };

      receiver = {
        enable = lib.mkEnableOption "heartbeat receiver that forwards to Gatus deadman endpoint";

        user = lib.mkOption {
          type = lib.types.str;
          default = "root";
          description = "User that runs the heartbeat receiver service.";
        };

        group = lib.mkOption {
          type = lib.types.str;
          default = "root";
          description = "Group that runs the heartbeat receiver service.";
        };

        listenAddress = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "Address to bind heartbeat receiver on.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 18080;
          description = "Port for heartbeat receiver.";
        };

        path = lib.mkOption {
          type = lib.types.str;
          default = "/heartbeat";
          description = "HTTP path for heartbeat receiver.";
        };

        gatusPort = lib.mkOption {
          type = lib.types.port;
          default = 8080;
          description = "Local Gatus API port.";
        };

        gatusTimeoutSeconds = lib.mkOption {
          type = lib.types.ints.positive;
          default = 5;
          description = "Timeout for forwarding heartbeat to Gatus API.";
        };

        externalEndpointName = lib.mkOption {
          type = lib.types.str;
          default = "heartbeat";
          description = "Gatus external endpoint name updated by this receiver.";
        };

        externalEndpointApiId = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Gatus external endpoint API id. Null derives <group>_<name>.";
        };

        deadmanGroup = lib.mkOption {
          type = lib.types.str;
          default = "deadman";
          description = "Gatus group for deadman endpoint.";
        };

        deadmanInterval = lib.mkOption {
          type = lib.types.str;
          default = "20m";
          description = "Expected heartbeat interval for Gatus deadman endpoint.";
        };

        deadmanAlert = {
          description = lib.mkOption {
            type = lib.types.str;
            default = "heartbeat missing";
            description = "Alert description for deadman failures.";
          };

          failureThreshold = lib.mkOption {
            type = lib.types.int;
            default = 1;
            description = "Consecutive failures before triggering alert.";
          };

          successThreshold = lib.mkOption {
            type = lib.types.int;
            default = 1;
            description = "Consecutive successes before resolving alert.";
          };

          sendOnResolved = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Send resolved notification for deadman endpoint.";
          };
        };
      };

      push = {
        enable = lib.mkEnableOption "periodic heartbeat push sender";

        user = lib.mkOption {
          type = lib.types.str;
          default = "root";
          description = "User that runs the heartbeat push service.";
        };

        group = lib.mkOption {
          type = lib.types.str;
          default = "root";
          description = "Group that runs the heartbeat push service.";
        };

        endpointUrl = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Target heartbeat URL. Null reads HEARTBEAT_URL from secret env.";
        };

        schedule = lib.mkOption {
          type = lib.types.str;
          default = "*:0/10";
          description = "systemd OnCalendar schedule for heartbeat pushes.";
        };

        randomizedDelaySec = lib.mkOption {
          type = lib.types.str;
          default = "2m";
          description = "Randomized delay for heartbeat push timer.";
        };

        connectTimeoutSeconds = lib.mkOption {
          type = lib.types.ints.positive;
          default = 5;
          description = "curl connect timeout for heartbeat push.";
        };

        requestTimeoutSeconds = lib.mkOption {
          type = lib.types.ints.positive;
          default = 15;
          description = "curl max-time for one heartbeat push attempt.";
        };

        retries = lib.mkOption {
          type = lib.types.addCheck lib.types.int (v: v >= 0);
          default = 2;
          description = "Number of retry attempts for heartbeat push.";
        };

        retryDelaySeconds = lib.mkOption {
          type = lib.types.addCheck lib.types.int (v: v >= 0);
          default = 2;
          description = "Delay between heartbeat push retry attempts.";
        };
      };
    };

    config = lib.mkMerge [
      (lib.mkIf cfg.receiver.enable {
        my.secrets.allowReadAccess = [
          {
            readers = [cfg.receiver.user];
            path = envFile;
          }
          {
            readers = ["gatus"];
            path = envFile;
          }
        ];

        systemd.services.gatus.serviceConfig.EnvironmentFile = lib.mkAfter [envFile];

        systemd.services.heartbeat-receiver = {
          description = "Heartbeat receiver forwarding to Gatus deadman endpoint";
          wantedBy = ["multi-user.target"];
          after = ["network-online.target"];
          wants = ["network-online.target"];
          serviceConfig = {
            Type = "simple";
            User = cfg.receiver.user;
            Group = cfg.receiver.group;
            EnvironmentFile = [envFile];
            ExecStart = "${pkgs.python3}/bin/python3 ${receiverScript}";
            Restart = "always";
            RestartSec = "2s";
          };
        };

        services.gatus.settings = {
          "external-endpoints" = [
            {
              name = cfg.receiver.externalEndpointName;
              group = cfg.receiver.deadmanGroup;
              token = "\${HEARTBEAT_PUSH_TOKEN}";
              heartbeat.interval = cfg.receiver.deadmanInterval;
              alerts = [
                {
                  type = "email";
                  inherit (receiverAlert) description;
                  "failure-threshold" = receiverAlert.failureThreshold;
                  "success-threshold" = receiverAlert.successThreshold;
                  "send-on-resolved" = receiverAlert.sendOnResolved;
                }
              ];
            }
          ];
        };

        networking.firewall.allowedTCPPorts = [cfg.receiver.port];
      })

      (lib.mkIf cfg.push.enable {
        my.secrets.allowReadAccess = [
          {
            readers = [cfg.push.user];
            path = envFile;
          }
        ];

        systemd.services.heartbeat-push = {
          description = "Push heartbeat to remote endpoint";
          after = ["network-online.target"];
          wants = ["network-online.target"];
          serviceConfig = {
            Type = "oneshot";
            User = cfg.push.user;
            Group = cfg.push.group;
            EnvironmentFile = envFile;
            ExecStart = pushScript;
          };
        };

        systemd.timers.heartbeat-push = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = cfg.push.schedule;
            Persistent = true;
            RandomizedDelaySec = cfg.push.randomizedDelaySec;
          };
        };
      })
    ];
  };
}
