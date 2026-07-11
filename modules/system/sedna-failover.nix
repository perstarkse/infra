_: {
  config.flake.nixosModules.sedna-failover = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.sedna-failover;

    tokenFile = cfg.dnsFailover.cloudflareApiTokenFile;
    apiBaseUrl = cfg.dnsFailover.cloudflareApiBaseUrl;
    tlsTokenFile = cfg.tls.cloudflareApiTokenFile;
    allDomains = lib.concatLists (map (zone: zone.domains) cfg.dnsFailover.zones);
    uniqueZones = lib.unique (map (zone: zone.zone) cfg.dnsFailover.zones);
    domainZoneMap = lib.flatten (map (zone:
      map (domain: {
        inherit domain;
        inherit (zone) zone;
      })
      zone.domains)
    cfg.dnsFailover.zones);

    # Derive a maintenance page from the branded HTML asset
    maintenancePage = pkgs.writeText "maintenance.html" ''
      <!DOCTYPE html>
      <html lang="en">
      <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>${cfg.maintenancePage.title}</title>
      <style>
        *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
        html, body { height: 100%; }

        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
          background: linear-gradient(160deg, #1a1a2e 0%, #16213e 40%, #0f3460 100%);
          color: #e2e8f0;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          min-height: 100vh;
          text-align: center;
          padding: 2rem;
          position: relative;
          overflow: hidden;
        }

        .floating-cats {
          position: fixed;
          inset: 0;
          pointer-events: none;
          z-index: 0;
        }

        .cat-emoji {
          position: absolute;
          font-size: 1.5rem;
          animation: catFloat linear infinite;
          opacity: 0.5;
        }

        @keyframes catFloat {
          0% { transform: translateY(110vh) rotate(0deg); opacity: 0; }
          10% { opacity: 0.5; }
          90% { opacity: 0.5; }
          100% { transform: translateY(-10vh) rotate(360deg); opacity: 0; }
        }

        .content {
          position: relative;
          z-index: 2;
          max-width: 560px;
        }

        .logo {
          font-size: 2.5rem;
          font-weight: 700;
          letter-spacing: -0.02em;
          margin-bottom: 1rem;
        }
        .logo span { color: #60a5fa; }

        .icon {
          font-size: 4rem;
          margin-bottom: 1.5rem;
          display: block;
        }

        h1 {
          font-size: 1.75rem;
          font-weight: 600;
          margin-bottom: 0.75rem;
          color: #f1f5f9;
        }

        p {
          font-size: 1.05rem;
          line-height: 1.6;
          color: #94a3b8;
          margin-bottom: 0.5rem;
        }

        .status-box {
          margin-top: 2rem;
          padding: 1rem 1.5rem;
          background: rgba(30, 41, 59, 0.7);
          border: 1px solid rgba(96, 165, 250, 0.2);
          border-radius: 10px;
          backdrop-filter: blur(6px);
        }
        .status-box p { font-size: 0.9rem; margin-bottom: 0.25rem; }
        .status-box .label { color: #64748b; text-transform: uppercase; font-size: 0.7rem; letter-spacing: 0.05em; }

        .footer {
          margin-top: 3rem;
          font-size: 0.8rem;
          color: #475569;
        }
        .footer a { color: #60a5fa; text-decoration: none; }

        @media (prefers-color-scheme: light) {
          body {
            background: linear-gradient(160deg, #fdf2e9 0%, #f5e6d3 40%, #e8d5c4 100%);
            color: #4a3728;
          }
          h1 { color: #2d1f14; }
          p { color: #6b5a4a; }
          .status-box { background: rgba(255,255,255,0.7); border-color: rgba(200,160,120,0.3); }
          .status-box .label { color: #8b7a6a; }
        }
      </style>
      </head>
      <body>
        <div class="floating-cats" aria-hidden="true" id="cat-container"></div>

        <div class="content">
          <span class="icon">${cfg.maintenancePage.pageIcon}</span>
          <div class="logo">stark.<span>pub</span></div>
          <h1>${cfg.maintenancePage.heading}</h1>
          ${lib.concatMapStringsSep "\n          " (line: ''
          <p>${line}</p>
        '')
        cfg.maintenancePage.bodyLines}
          <div class="status-box">
            <p class="label">Status</p>
            <p>${cfg.maintenancePage.statusText}</p>
          </div>
          <div class="footer">
            ${lib.concatStringsSep " · " (map (link: "<a href=\"${link.url}\">${link.label}</a>") cfg.maintenancePage.links)}
          </div>
        </div>

        <script>
          (function() {
            var container = document.getElementById('cat-container');
            var emojis = ['🐱', '😸', '😺', '😻', '🐈', '🐾', '💻', '☕'];
            var count = ${toString cfg.maintenancePage.floatingEmojiCount};
            for (var i = 0; i < count; i++) {
              var el = document.createElement('div');
              el.className = 'cat-emoji';
              el.textContent = emojis[i % emojis.length];
              el.style.left = (Math.random() * 100) + '%';
              el.style.animationDuration = (8 + Math.random() * 12) + 's';
              el.style.animationDelay = (-Math.random() * 15) + 's';
              el.style.fontSize = (1 + Math.random() * 1.5) + 'rem';
              container.appendChild(el);
            }
          })();
        </script>
      </body>
      </html>
    '';

    maintenanceRoot = pkgs.runCommand "maintenance-page-root" {} ''
      mkdir -p "$out"
      cp ${maintenancePage} "$out/index.html"
    '';
    maintenanceLocation = {
      root = maintenanceRoot;
      tryFiles = "$uri /index.html";
      extraConfig = ''
        add_header Cache-Control "public, max-age=60";
      '';
    };

    # Cloudflare DNS update script (failover: point domains → Sedna)
    dnsFailoverScript = pkgs.writeShellScript "cloudflare-dns-failover" ''
      set -euo pipefail

      CF_API_TOKEN_FILE="${tokenFile}"
      if [ ! -f "$CF_API_TOKEN_FILE" ]; then
        echo "ERROR: Cloudflare API token file not found at $CF_API_TOKEN_FILE"
        echo "Create the file or configure my.sedna-failover.dnsFailover.cloudflareApiTokenFile"
        exit 0
      fi
      CF_RAW="$(cat "$CF_API_TOKEN_FILE")"
      # Strip KEY=VALUE prefix if present (systemd EnvironmentFile format)
      case "$CF_RAW" in
        *_TOKEN=*|*_KEY=*) CF_TOKEN="''${CF_RAW#*=}" ;;
        *) CF_TOKEN="$CF_RAW" ;;
      esac
      SEDNA_IP="${cfg.dnsFailover.sednaPublicIp}"
      STATE_FILE="/var/lib/sedna-failover/dns-state.json"

      mkdir -p "$(dirname "$STATE_FILE")"
      echo "[]" > "$STATE_FILE.tmp"

      ${lib.concatMapStringsSep "\n" ({
          zone,
          zoneId,
          domains,
        }: let
          domainArgs = lib.concatMapStringsSep " " (domain: "'${domain}'") domains;
        in ''
          echo "=== Zone: ${zone} ==="
          for domain in ${domainArgs}; do
            echo "  Looking up DNS record for $domain..."

            # Get record ID, current content, and proxy status
            resp=$(${pkgs.curl}/bin/curl -fsS \
              -H "Authorization: Bearer $CF_TOKEN" \
              -H "Content-Type: application/json" \
              "${apiBaseUrl}/zones/${zoneId}/dns_records?type=A&name=$domain")

            record_id=$(echo "$resp" | ${pkgs.jq}/bin/jq -r '.result[0].id // empty')
            current_ip=$(echo "$resp" | ${pkgs.jq}/bin/jq -r '.result[0].content // empty')
            proxied=$(echo "$resp" | ${pkgs.jq}/bin/jq -r '.result[0].proxied // false')

            if [ -z "$record_id" ]; then
              echo "  WARNING: No A record found for $domain, skipping"
              continue
            fi

            if [ "$current_ip" = "$SEDNA_IP" ]; then
              echo "  Already pointing to Sedna ($SEDNA_IP), skipping"
              continue
            fi

            # Save original IP for revert
            ${pkgs.jq}/bin/jq --arg d "$domain" --arg ip "$current_ip" --arg prox "$proxied" \
              '. += [{"domain": $d, "original_ip": $ip, "original_proxied": $prox}]' \
              "$STATE_FILE.tmp" > "$STATE_FILE.tmp2"
            mv "$STATE_FILE.tmp2" "$STATE_FILE.tmp"

            # Update DNS record to Sedna's IP
            update_resp=$(${pkgs.curl}/bin/curl -fsS -X PATCH \
              -H "Authorization: Bearer $CF_TOKEN" \
              -H "Content-Type: application/json" \
              -d "{\"content\":\"$SEDNA_IP\",\"ttl\":120,\"proxied\":$proxied}" \
              "${apiBaseUrl}/zones/${zoneId}/dns_records/$record_id")

            if echo "$update_resp" | ${pkgs.jq}/bin/jq -e '.success == true' >/dev/null 2>&1; then
              echo "  ✓ $domain → $SEDNA_IP"
            else
              err=$(echo "$update_resp" | ${pkgs.jq}/bin/jq -r '.errors[0].message // "unknown"')
              echo "  ✗ Failed to update $domain: $err"
            fi
          done
        '')
        cfg.dnsFailover.zones}

      mv "$STATE_FILE.tmp" "$STATE_FILE"
      echo "=== Failover complete ==="
    '';

    # Cloudflare DNS revert script (point domains back to original IPs)
    dnsRevertScript = pkgs.writeShellScript "cloudflare-dns-revert" ''
      set -euo pipefail

      CF_API_TOKEN_FILE="${tokenFile}"
      if [ ! -f "$CF_API_TOKEN_FILE" ]; then
        echo "ERROR: Cloudflare API token file not found at $CF_API_TOKEN_FILE"
        exit 0
      fi
      CF_RAW="$(cat "$CF_API_TOKEN_FILE")"
      # Strip KEY=VALUE prefix if present (systemd EnvironmentFile format)
      case "$CF_RAW" in
        *_TOKEN=*|*_KEY=*) CF_TOKEN="''${CF_RAW#*=}" ;;
        *) CF_TOKEN="$CF_RAW" ;;
      esac
      STATE_FILE="/var/lib/sedna-failover/dns-state.json"

      if [ ! -f "$STATE_FILE" ]; then
        echo "No DNS state file found. Nothing to revert."
        exit 0
      fi

      ${lib.concatMapStringsSep "\n" ({
          zone,
          zoneId,
          domains,
        }: let
          domainArgs = lib.concatMapStringsSep " " (domain: "'${domain}'") domains;
        in ''
          echo "=== Zone: ${zone} ==="
          for domain in ${domainArgs}; do
            echo "  Looking up DNS record for $domain..."

            resp=$(${pkgs.curl}/bin/curl -fsS \
              -H "Authorization: Bearer $CF_TOKEN" \
              -H "Content-Type: application/json" \
              "${apiBaseUrl}/zones/${zoneId}/dns_records?type=A&name=$domain")

            record_id=$(echo "$resp" | ${pkgs.jq}/bin/jq -r '.result[0].id // empty')

            if [ -z "$record_id" ]; then
              echo "  WARNING: No A record found for $domain, skipping"
              continue
            fi

            # Get original IP from state file
            original_ip=$(${pkgs.jq}/bin/jq -r --arg d "$domain" '.[] | select(.domain == $d) | .original_ip // empty' "$STATE_FILE")
            original_proxied=$(${pkgs.jq}/bin/jq -r --arg d "$domain" '.[] | select(.domain == $d) | .original_proxied // "true"' "$STATE_FILE")

            if [ -z "$original_ip" ]; then
              echo "  No state found for $domain, skipping"
              continue
            fi

            current_ip=$(echo "$resp" | ${pkgs.jq}/bin/jq -r '.result[0].content // empty')
            if [ "$current_ip" = "$original_ip" ]; then
              echo "  Already at original IP ($original_ip), skipping"
              continue
            fi

            # Revert DNS record to original IP
            update_resp=$(${pkgs.curl}/bin/curl -fsS -X PATCH \
              -H "Authorization: Bearer $CF_TOKEN" \
              -H "Content-Type: application/json" \
              -d "{\"content\":\"$original_ip\",\"ttl\":120,\"proxied\":$original_proxied}" \
              "${apiBaseUrl}/zones/${zoneId}/dns_records/$record_id")

            if echo "$update_resp" | ${pkgs.jq}/bin/jq -e '.success == true' >/dev/null 2>&1; then
              echo "  ✓ $domain → $original_ip"
            else
              err=$(echo "$update_resp" | ${pkgs.jq}/bin/jq -r '.errors[0].message // "unknown"')
              echo "  ✗ Failed to revert $domain: $err"
            fi
          done
        '')
        cfg.dnsFailover.zones}

      # Clear state file after successful revert
      rm -f "$STATE_FILE"
      echo "=== Revert complete ==="
    '';

    # Heartbeat health check script
    healthCheckScript = pkgs.writeShellScript "failover-health-check" ''
      set -euo pipefail

      STATE_FILE="/var/lib/sedna-failover/dns-state.json"
      HEARTBEAT_TIMEOUT_SECONDS=$(( ${toString cfg.dnsFailover.heartbeatTimeoutMinutes} * 60 ))
      TIMESTAMP_FILE="${cfg.dnsFailover.heartbeatTimestampFile}"

      IN_FAILOVER=$(test -f "$STATE_FILE" && ${pkgs.jq}/bin/jq 'length > 0' "$STATE_FILE" 2>/dev/null || echo "false")

      if [ -n "$TIMESTAMP_FILE" ] && [ -f "$TIMESTAMP_FILE" ] && [ -r "$TIMESTAMP_FILE" ]; then
        LAST_HEARTBEAT=$(cat "$TIMESTAMP_FILE")
        NOW=$(date +%s)
        ELAPSED=$(( NOW - LAST_HEARTBEAT ))

        echo "Last heartbeat: $(date -d @$LAST_HEARTBEAT 2>/dev/null || echo $LAST_HEARTBEAT)"
        echo "Seconds since last heartbeat: $ELAPSED"
        echo "Timeout: $HEARTBEAT_TIMEOUT_SECONDS seconds"
        echo "In failover mode: $IN_FAILOVER"

        if [ "$ELAPSED" -lt "$HEARTBEAT_TIMEOUT_SECONDS" ]; then
          echo "IO is healthy."
          if [ "$IN_FAILOVER" = "true" ]; then
            ${
        if cfg.dnsFailover.skipDnsRevert
        then ''
          echo "skipDnsRevert enabled: clearing failover state, letting ddclient on IO restore DNS."
          rm -f "$STATE_FILE"
        ''
        else ''
          echo "Reverting DNS to original IPs..."
          exec ${dnsRevertScript}
        ''
      }
          else
            echo "DNS is normal. Nothing to do."
          fi
        else
          echo "IO heartbeat lost! Triggering failover..."
          if [ "$IN_FAILOVER" = "false" ]; then
            exec ${dnsFailoverScript}
          else
            echo "Already in failover mode. Nothing to do."
          fi
        fi
      else
        echo "WARNING: Heartbeat timestamp file not found at $TIMESTAMP_FILE"
        echo "No heartbeat ever recorded. Assuming IO is down."
        if [ "$IN_FAILOVER" = "false" ]; then
          exec ${dnsFailoverScript}
        else
          echo "Already in failover mode. Nothing to do."
        fi
      fi
    '';
  in {
    options.my.sedna-failover = {
      enable = lib.mkEnableOption "Sedna failover with branded maintenance page and heartbeat-driven DNS failover";

      maintenancePage = {
        title = lib.mkOption {
          type = lib.types.str;
          default = "stark.pub — Offline";
          description = "Browser tab title for the maintenance page.";
        };

        pageIcon = lib.mkOption {
          type = lib.types.str;
          default = "🐱";
          description = "Main icon displayed on the page (any emoji or HTML).";
        };

        heading = lib.mkOption {
          type = lib.types.str;
          default = "The cats are taking a nap";
          description = "Main heading displayed on the page.";
        };

        bodyLines = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "Our server hamsters have unionized and are demanding better treats."
            "We've sent someone to negotiate, but they got distracted petting the cats."
            "Services will resume shortly — or whenever the cats decide."
          ];
          description = "Paragraph lines shown below the heading.";
        };

        statusText = lib.mkOption {
          type = lib.types.str;
          default = "Infrastructure offline — automatic recovery pending cat nap";
          description = "Status box text shown on the maintenance page.";
        };

        floatingEmojiCount = lib.mkOption {
          type = lib.types.int;
          default = 40;
          description = "Number of animated floating emojis on the page.";
        };

        links = lib.mkOption {
          type = lib.types.listOf (lib.types.submodule {
            options = {
              label = lib.mkOption {
                type = lib.types.str;
                description = "Link text.";
              };
              url = lib.mkOption {
                type = lib.types.str;
                description = "Link URL.";
              };
            };
          });
          default = [
            {
              label = "Contact";
              url = "mailto:services@stark.pub";
            }
          ];
          description = "Footer links on the maintenance page.";
        };
      };

      dnsFailover = {
        enable = lib.mkEnableOption "heartbeat-driven Cloudflare DNS failover";

        ioPublicIp = lib.mkOption {
          type = lib.types.str;
          description = "IO's current public IP. The failover script saves the actual DNS value before switching, so this is only used for verification.";
        };

        sednaPublicIp = lib.mkOption {
          type = lib.types.str;
          description = "Sedna's public IP address where traffic should be redirected during failover.";
        };

        skipDnsRevert = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Skip DNS record revert when IO comes back. Lets ddclient on IO update DNS naturally. Avoids split-brain if IO's public IP changed during the outage.";
        };

        heartbeatTimeoutMinutes = lib.mkOption {
          type = lib.types.int;
          default = 5;
          description = "Minutes without a heartbeat before triggering failover.";
        };

        checkInterval = lib.mkOption {
          type = lib.types.str;
          default = "*:0/2";
          description = "systemd OnCalendar interval for failover health checks.";
        };

        cloudflareApiTokenFile = lib.mkOption {
          type = lib.types.path;
          default = "/run/secrets/vars/api-key-cloudflare-dns/api-token";
          description = "Path to a file containing the Cloudflare API token. The file must be readable by the failover-check user.";
        };

        cloudflareApiBaseUrl = lib.mkOption {
          type = lib.types.str;
          default = "https://api.cloudflare.com/client/v4";
          description = "Cloudflare API base URL. Override in tests with a local mock server.";
        };

        heartbeatTimestampFile = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/heartbeat/last-heartbeat";
          description = "Path to the heartbeat timestamp file written by the heartbeat receiver. Use a StateDirectory path (e.g. /var/lib/<name>/...) since /tmp and /var/tmp are namespaced by PrivateTmp.";
        };

        zones = lib.mkOption {
          type = lib.types.listOf (lib.types.submodule {
            options = {
              zone = lib.mkOption {
                type = lib.types.str;
                description = "Cloudflare zone name (e.g. stark.pub).";
              };
              zoneId = lib.mkOption {
                type = lib.types.str;
                description = "Cloudflare zone ID for the zone.";
              };
              domains = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                description = "Domains to update during failover.";
              };
            };
          });
          default = [];
          description = "Cloudflare zones and domains to manage during failover.";
        };
      };

      tls = {
        enable = lib.mkEnableOption "HTTPS for failover domains via DNS-01 wildcard certificates";

        acmeEmail = lib.mkOption {
          type = lib.types.str;
          default = "services@stark.pub";
          description = "Contact email for ACME certificate registration.";
        };

        cloudflareApiTokenFile = lib.mkOption {
          type = lib.types.path;
          default = "/run/secrets/vars/api-key-cloudflare-dns/api-token";
          description = "Cloudflare API token file for DNS-01 ACME challenges. Must be readable by the nginx group.";
        };
      };
    };

    config = lib.mkIf cfg.enable (lib.mkMerge [
      {
        services.nginx = {
          enable = true;
          recommendedTlsSettings = lib.mkIf cfg.tls.enable true;
          virtualHosts =
            if cfg.tls.enable && allDomains != []
            then
              lib.listToAttrs (map ({
                domain,
                zone,
              }:
                lib.nameValuePair domain {
                  useACMEHost = zone;
                  enableACME = false;
                  forceSSL = true;
                  locations."/" = maintenanceLocation;
                  extraConfig = ''
                    add_header Access-Control-Allow-Origin "*" always;
                  '';
                })
              domainZoneMap)
            else {
              "_" = {
                default = true;
                locations."/" = maintenanceLocation;
                extraConfig = ''
                  add_header Access-Control-Allow-Origin "*" always;
                '';
              };
            };
        };

        networking.firewall.allowedTCPPorts =
          [80]
          ++ lib.optionals cfg.tls.enable [443];
      }

      (lib.mkIf cfg.tls.enable {
        security.acme = {
          acceptTerms = true;
          defaults.email = cfg.tls.acmeEmail;
        };

        security.acme.certs = lib.listToAttrs (map (zone:
          lib.nameValuePair zone {
            dnsProvider = "cloudflare";
            group = "nginx";
            environmentFile = tlsTokenFile;
            extraDomainNames = ["*.${zone}"];
          })
        uniqueZones);
      })

      (lib.mkIf cfg.dnsFailover.enable {
        users.users.failover-check = {
          isSystemUser = true;
          group = "failover-check";
          description = "Failover DNS check service user";
        };
        users.groups.failover-check = {};

        systemd.services.failover-check = {
          description = "Check IO heartbeat and trigger Cloudflare DNS failover if needed";
          after = ["network-online.target"];
          wants = ["network-online.target"];
          serviceConfig = {
            Type = "oneshot";
            User = "failover-check";
            Group = "failover-check";
            StateDirectory = "sedna-failover";
            StateDirectoryMode = "0755";
            ExecStart = healthCheckScript;
            CapabilityBoundingSet = "";
            LockPersonality = true;
            MemoryDenyWriteExecute = true;
            NoNewPrivileges = true;
            PrivateDevices = true;
            PrivateTmp = true;
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectHome = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectSystem = "full";
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
              "AF_UNIX"
            ];
            RestrictNamespaces = true;
            RestrictRealtime = true;
            SystemCallArchitectures = "native";
            UMask = "0077";
          };
        };

        systemd.timers.failover-check = {
          description = "Periodic failover health check timer";
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = cfg.dnsFailover.checkInterval;
            Persistent = true;
            RandomizedDelaySec = "30s";
          };
        };
      })
    ]);
  };
}
