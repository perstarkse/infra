_: {
  config.flake.nixosModules.heartbeat = {
    config,
    lib,
    pkgs,
    mkHardenedServiceConfig,
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

    tlsEnabled =
      cfg.receiver.tls.enable && cfg.receiver.tls.certFile != null && cfg.receiver.tls.keyFile != null;

    receiverScript = pkgs.writeText "heartbeat-receiver.py" ''
      import http.server
      import hmac
      import os
      import ssl
      import urllib.parse
      import urllib.request

      LISTEN = ("${cfg.receiver.listenAddress}", ${toString cfg.receiver.port})
      # Bound per-connection TLS handshakes so a client that connects and goes
      # silent cannot pin a thread forever.
      TLS_HANDSHAKE_TIMEOUT_SECONDS = 10
      EXPECTED_PATH = "${endpointPath}"
      PUSH_TOKEN = os.environ["HEARTBEAT_PUSH_TOKEN"]
      TLS_CERT_FILE = "${
        if tlsEnabled
        then toString cfg.receiver.tls.certFile
        else ""
      }"
      TLS_KEY_FILE = "${
        if tlsEnabled
        then toString cfg.receiver.tls.keyFile
        else ""
      }"
      GATUS_URL = "http://127.0.0.1:${toString cfg.receiver.gatusPort}/api/v1/endpoints/${receiverEndpointApiId}/external?success=true&duration=1ms"
      TIMESTAMP_FILE = "${lib.optionalString (cfg.receiver.heartbeatTimestampFile != null) cfg.receiver.heartbeatTimestampFile}"


      def _write_timestamp():
          import time as _time

          _tmp = TIMESTAMP_FILE + ".tmp"
          with open(_tmp, "w") as _f:
              _f.write(str(int(_time.time())) + "\n")
          os.replace(_tmp, TIMESTAMP_FILE)


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
              # Timestamp is the source of truth for DNS failover; gatus is
              # best-effort. A prior version wrote the timestamp only after a
              # successful gatus forward, so a gatus outage made every push
              # return 502 and the health-check saw "heartbeat lost" even
              # though io was healthy. Write first, then forward.
              try:
                  if TIMESTAMP_FILE:
                      _write_timestamp()
              except Exception:
                  pass

              try:
                  with urllib.request.urlopen(req, timeout=${toString cfg.receiver.gatusTimeoutSeconds}):
                      pass
              except Exception:
                  # Gatus down must not wedge failover: timestamp already
                  # written, so DNS stays healthy. Return 502 so the sender
                  # can retry, but failover will not trigger.
                  self.send_response(502)
                  self.end_headers()
                  return

              self.send_response(204)
              self.end_headers()


      class Server(http.server.ThreadingHTTPServer):
          """Threading server that terminates TLS per accepted connection.

          Wrapping the listening socket (ctx.wrap_socket(httpd.socket, ...)) is a
          footgun: SSLSocket.accept() performs the handshake synchronously in
          the accept loop, so one client that connects and goes silent wedges
          the whole receiver with a full SYN backlog (seen 2026-08-26: a
          scanner stall made every heartbeat push time out from everywhere,
          indistinguishable from a firewall DROP). Wrapping the accepted socket
          with do_handshake_on_connect=False moves the handshake into a worker
          thread, bounded by the timeout above.
          """

          daemon_threads = True
          request_queue_size = 128

          def __init__(self, addr, handler, ssl_context):
              super().__init__(addr, handler)
              self._ssl_context = ssl_context

          def get_request(self):
              sock, addr = super().get_request()
              if self._ssl_context is None:
                  return sock, addr
              # SSLSocket inherits the timeout, so the deferred handshake in the
              # worker thread gives up after TLS_HANDSHAKE_TIMEOUT_SECONDS.
              sock.settimeout(TLS_HANDSHAKE_TIMEOUT_SECONDS)
              return self._ssl_context.wrap_socket(
                  sock, server_side=True, do_handshake_on_connect=False
              ), addr

      def _build_server():
          if TLS_CERT_FILE:
              ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
              ctx.minimum_version = ssl.TLSVersion.TLSv1_2
              ctx.load_cert_chain(certfile=TLS_CERT_FILE, keyfile=TLS_KEY_FILE)
          else:
              ctx = None
          return Server(LISTEN, Handler, ctx)

      with _build_server() as httpd:
          httpd.serve_forever()
    '';

    # Private-CA pinning: the heartbeat endpoint is a raw IP on the public
    # internet, so there is no ACME name to validate against.
    pushCurlArgs = lib.concatStringsSep " \\\n        " (
      [
        "--connect-timeout ${toString cfg.push.connectTimeoutSeconds}"
        "--max-time ${toString cfg.push.requestTimeoutSeconds}"
        "--retry ${toString cfg.push.retries}"
        "--retry-delay ${toString cfg.push.retryDelaySeconds}"
        "--retry-all-errors"
      ]
      ++ lib.optionals (cfg.push.caCertFile != null) [
        ''--cacert "${toString cfg.push.caCertFile}"''
      ]
    );

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

      ${pkgs.curl}/bin/curl -fsS \
        ${pushCurlArgs} \
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

        tls = {
          enable = lib.mkEnableOption ''
            TLS termination on the receiver socket.

            For receivers reachable over untrusted networks (e.g. a WAN-facing
            deadman endpoint): the bearer token must not transit plaintext.
            Pair with push.caCertFile on senders (private-CA pinning).'';

          certFile = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "Server certificate chain (PEM).";
          };

          keyFile = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "Server private key (PEM).";
          };
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
          # Track the Gatus API port so the deadman callback cannot silently
          # diverge from where Gatus actually listens (both defaults were 8080).
          default = (config.my.remote-monitoring or {}).webPort or 8080;
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

        heartbeatTimestampFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "File path to write the last heartbeat Unix timestamp on each valid heartbeat reception. Used by external failover monitors.";
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

        caCertFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "CA bundle passed to curl --cacert. Required when the endpoint uses https with a private CA.";
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
        assertions = [
          {
            assertion = !cfg.receiver.tls.enable || (cfg.receiver.tls.certFile != null && cfg.receiver.tls.keyFile != null);
            message = "my.heartbeat.receiver.tls.enable requires both tls.certFile and tls.keyFile.";
          }
        ];

        my.secrets.allowReadAccess =
          [
            {
              readers = [cfg.receiver.user "gatus"];
              path = envFile;
            }
          ]
          ++ lib.optionals tlsEnabled [
            {
              readers = [cfg.receiver.user];
              path = cfg.receiver.tls.certFile;
            }
            {
              readers = [cfg.receiver.user];
              path = cfg.receiver.tls.keyFile;
            }
          ];

        systemd.services.gatus.serviceConfig.EnvironmentFile = lib.mkAfter [envFile];

        systemd.services.heartbeat-receiver = {
          description = "Heartbeat receiver forwarding to Gatus deadman endpoint";
          wantedBy = ["multi-user.target"];
          after = ["network-online.target"];
          wants = ["network-online.target"];
          serviceConfig =
            {
              Type = "simple";
              User = cfg.receiver.user;
              Group = cfg.receiver.group;
              EnvironmentFile = [envFile];
              ExecStart = "${pkgs.python3}/bin/python3 ${receiverScript}";
              Restart = "always";
              RestartSec = "2s";
            }
            // mkHardenedServiceConfig {
              stateDirectory = "heartbeat";
              protectSystem = "strict";
              restrictAddressFamilies = ["AF_INET"];
              umask = "0022";
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
