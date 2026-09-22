{
  ctx,
  config,
  lib,
  ...
}: let
  # Public-domain registry is mirrored in flake.lib.publicDomains (pure
  # constant, no cross-machine eval — arch #6). The derived projection here
  # MUST equal it: io's registry-equality lint fails the build on drift, and
  # sedna's subset assertions fail if a failover/gatus domain leaves the
  # registry. Failover and gatus consume explicit subsets; a forgotten domain
  # fails the build instead of silently skipping failover/gatus coverage.
  # NOTE: when adding a public domain, update BOTH this derivation chain
  # (endpoints vhost or my.publicDnsRecords) AND flake.lib.publicDomains.
  publicDomains = ctx.flake.lib.publicDomains;
  # Domains that should repoint to sedna's maintenance page during an io outage.
  failoverDomains = [
    "minne.stark.pub"
    "minne-demo.stark.pub"
    "request.stark.pub"
    "politikerstod.stark.pub"
    "orebro.politikerstod.stark.pub"
    "wake.stark.pub"
    "nous.fyi"
  ];
  # Domains that answer HTTPS on io and get active health checks from gatus.
  httpMonitoredDomains = [
    "request.stark.pub"
    "minne.stark.pub"
    "nous.fyi"
    "politikerstod.stark.pub"
    "wake.stark.pub"
  ];
  zoneIds = {
    "stark.pub" = "5b35b4cd4229d502a964e052f18dd650";
    "nous.fyi" = "88916637654e3923f7669c7fd59ca76a";
  };
in {
  imports =
    (with ctx.flake.nixosModules; [
      options
      shared
      heartbeat
      remote-monitoring
      sedna-failover
      backup-mx
      ntfy
    ])
    ++ (with ctx.inputs.varsHelper.nixosModules; [default]);

  swapDevices = [
    {
      device = "/swapfile";
      size = 4096;
    }
  ];

  my = {
    mainUser = {
      enable = false;
      name = "p";
    };

    secrets = {
      discover = {
        enable = true;
        includeTags = [
          "gatus"
          "heartbeat"
          "cloudflare"
          "ntfy"
        ];
      };
      # Fail closed when an expected generator is absent after merge
      # (tag typo, missing includeTags) instead of deploying a machine
      # whose services reference secrets that exist nowhere.
      requireGenerators = ["api-key-cloudflare-dns" "gatus" "heartbeat" "heartbeat-tls" "ntfy"];

      allowReadAccess = [
        {
          readers = ["failover-check" "nginx"];
          path = config.my.secrets.getPath "api-key-cloudflare-dns" "api-token";
        }
      ];
    };

    sedna-failover = {
      enable = true;

      maintenancePage = {
        title = "stark.pub — The cats are napping";
        heading = "The cats are napping";
        bodyLines = [
          "Our server cats have unionized and are demanding better treats."
          "We've sent someone to negotiate, but they got distracted petting the cats."
          "Services will resume shortly."
        ];
        statusText = "Infrastructure offline — automatic recovery pending cat nap";
        links = [
          {
            label = "Contact";
            url = "mailto:services@stark.pub";
          }
        ];
      };

      dnsFailover = {
        enable = true;
        sednaPublicIp = "130.61.55.4";
        # io's heartbeat push runs on *:0/5 with a 2m randomized delay, so a
        # healthy inter-arrival gap reaches ~7 min. The 5 min default timeout
        # false-triggered failover on normal jitter (866 "heartbeat lost"
        # events / 7 days). 10 min exceeds the worst healthy gap and matches
        # the 15m deadmanInterval configured below.
        heartbeatTimeoutMinutes = 10;
        # skipDnsRevert defaults to false (self-healing revert via stored
        # dns-state.json); see the option description for the 2026-09-02
        # incident rationale.
        cloudflareApiTokenFile = config.my.secrets.getPath "api-key-cloudflare-dns" "api-token";

        zones = lib.mapAttrsToList (zone: domains: {
          inherit zone domains;
          zoneId = zoneIds.${zone};
        }) (lib.groupBy (d: publicDomains.${d}) failoverDomains);
      };

      tls = {
        enable = true;
        cloudflareApiTokenFile = config.my.secrets.getPath "api-key-cloudflare-dns" "api-token";
      };
    };

    remote-monitoring = {
      enable = true;
      settings = {
        alerting.email = {
          host = "\${GATUS_SMTP_HOST}";
          port = 587;
          from = "\${GATUS_SMTP_FROM}";
          username = "\${GATUS_SMTP_USERNAME}";
          password = "\${GATUS_SMTP_PASSWORD}";
          to = "\${GATUS_ALERT_EMAIL_TO}";
          "default-alert" = {
            "failure-threshold" = 2;
            "success-threshold" = 1;
            "send-on-resolved" = true;
          };
        };

        endpoints =
          (map (domain: {
              name = domain;
              group = "public-http";
              url = "https://${domain}";
              interval = "2m";
              conditions = [
                "[STATUS] == 200"
                "[RESPONSE_TIME] < 4000"
                "[CERTIFICATE_EXPIRATION] > 168h"
              ];
              alerts = [
                {
                  type = "email";
                  description = "${domain} health check failed";
                  "failure-threshold" = 2;
                  "success-threshold" = 1;
                  "send-on-resolved" = true;
                }
              ];
            })
            httpMonitoredDomains)
          ++ [
            {
              name = "minne-demo.stark.pub";
              group = "public-http";
              url = "https://minne-demo.stark.pub";
              interval = "2m";
              conditions = [
                "[STATUS] >= 200"
                "[STATUS] < 400"
                "[RESPONSE_TIME] < 4000"
                "[CERTIFICATE_EXPIRATION] > 168h"
              ];
              alerts = [
                {
                  type = "email";
                  description = "minne-demo redirect check failed";
                  "failure-threshold" = 2;
                  "success-threshold" = 1;
                  "send-on-resolved" = true;
                }
              ];
            }
            {
              name = "mail-smtps";
              group = "public-mail";
              url = "tls://mail.stark.pub:465";
              interval = "5m";
              conditions = [
                "[CONNECTED] == true"
                "[CERTIFICATE_EXPIRATION] > 168h"
              ];
              alerts = [
                {
                  type = "email";
                  description = "SMTPS on mail.stark.pub failed";
                  "failure-threshold" = 2;
                  "success-threshold" = 1;
                  "send-on-resolved" = true;
                }
              ];
            }
            {
              name = "mail-imaps";
              group = "public-mail";
              url = "tls://mail.stark.pub:993";
              interval = "5m";
              conditions = [
                "[CONNECTED] == true"
                "[CERTIFICATE_EXPIRATION] > 168h"
              ];
              alerts = [
                {
                  type = "email";
                  description = "IMAPS on mail.stark.pub failed";
                  "failure-threshold" = 2;
                  "success-threshold" = 1;
                  "send-on-resolved" = true;
                }
              ];
            }
            {
              name = "plex-tcp";
              group = "public-tcp";
              url = "tcp://mail.stark.pub:32400";
              interval = "5m";
              conditions = ["[CONNECTED] == true"];
              alerts = [
                {
                  type = "email";
                  description = "plex-tcp health check failed";
                  "failure-threshold" = 3;
                  "success-threshold" = 1;
                  "send-on-resolved" = true;
                }
              ];
            }
          ];
      };
    };

    heartbeat.receiver = {
      enable = true;
      user = "heartbeat";
      group = "heartbeat";
      listenAddress = "0.0.0.0";
      # WAN-facing deadman endpoint: terminate TLS on the receiver socket so
      # io's bearer token never transits plaintext (review 2026-08-25). The
      # cert SAN covers 130.61.55.4; io pins the private CA.
      tls = {
        enable = true;
        certFile = config.my.secrets.getPath "heartbeat-tls" "server-cert.pem";
        keyFile = config.my.secrets.getPath "heartbeat-tls" "server-key.pem";
      };
      externalEndpointName = "io-heartbeat";
      deadmanInterval = "15m";
      deadmanAlert.description = "io heartbeat missing";
      # /var/lib/heartbeat/ via StateDirectory (outside PrivateTmp namespace)
      heartbeatTimestampFile = "/var/lib/heartbeat/last-heartbeat";
      # Freshness deadmen for every server backup job (single source:
      # flake.lib.backupJobs — no cross-machine eval, arch #6).
      backupJobs = ctx.flake.lib.backupJobs;
    };

    # Off-LAN alert relay (direct-A ntfy.stark.pub → 130.61.55.4, DNS-only).
    # my.ntfy.endpoints is internal-only, so no endpoint import applies here;
    # TLS reuses the *.stark.pub DNS-01 wildcard from sedna-failover.
    ntfy = {
      enable = true;
      address = "127.0.0.1";
      port = 2586;
      baseUrl = "https://ntfy.stark.pub";
      endpoints.enable = false;
    };
  };

  services.nginx.virtualHosts."ntfy.stark.pub" = {
    useACMEHost = "stark.pub";
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:2586";
      proxyWebsockets = true;
      extraConfig = ''
        client_max_body_size 0;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_read_timeout 1h;
        proxy_send_timeout 1h;
      '';
    };
  };

  services = {
    # Bound the journal: 1.8 GB on a 46 GB disk, with sshd preauth-scan noise
    # (~52k lines/week) being the main contributor. Unbounded growth on a 1 GB
    # VPS is a standing footgun.
    journald.extraConfig = "SystemMaxUse=256M\nSystemMaxFileSize=64M\n";

    avahi.enable = lib.mkForce false;

    openssh = {
      ports = [2222];
      settings = {
        KbdInteractiveAuthentication = false;
        PasswordAuthentication = false;
        PermitRootLogin = "prohibit-password";
      };
    };

    endlessh = {
      enable = true;
      port = 22;
      openFirewall = true;
    };

    # Direct-A publish endpoint (ntfy.stark.pub, no Cloudflare shield), so
    # auth-failure scanning gets a jail on the ntfy journal (makemake runs
    # the same stock-filter pattern for postfix/dovecot).
    fail2ban = {
      enable = true;
      maxretry = 5;
      bantime = "1h";
      ignoreIP = [
        "127.0.0.0/8"
        "::1"
      ];
      jails = {
        ntfy = {
          settings = {
            enabled = true;
            filter = "ntfy";
            backend = "systemd";
            journalmatch = "_SYSTEMD_UNIT=ntfy-sh.service";
            maxretry = 5;
            findtime = "10m";
            bantime = "1h";
          };
        };
      };
    };
  };

  # NOTE: exactly one <HOST> per failregex line. fail2ban expands <HOST> to
  # named ip4/ip6/dns groups, so two <HOST> on one line fails to compile and
  # takes the whole fail2ban server (incl. the sshd jail) down with exit 255
  # — seen 2026-09-21 on first deploy. Separate lines are ORed in their own
  # group namespace and are safe. Shapes are generic on purpose: ntfy-sh has
  # emitted no auth-failure line to the journal yet, so tighten to its exact
  # log format once the first 401/403 is observed (fail2ban-regex to verify).
  environment.etc."fail2ban/filter.d/ntfy.local".text = ''
    [Definition]
    failregex = ^<HOST> - \S+ \[[^\]]+\] "(?:GET|POST|PUT|DELETE) [^"]*" (?:401|403)\b
                ^\S+ .* ip=<HOST> .* (?:401|403|unauthorized|access denied)\b
                ^\S+ .* client:\s*<HOST> .* (?:401|403)\b
    ignoreregex =
  '';

  networking.firewall.allowedTCPPorts = [
    2222
  ];

  my.backupMx.enable = true;
  my.backupMx.queueWatch.smtpEnvFile = config.my.secrets.getPath "gatus" "env";

  # Failover/revert notices ride the same off-LAN smtp2go leg as the backup-MX
  # queue watch: it is the one publisher proven to survive both io and
  # makemake being down. Transition-only (see modules/system/sedna-failover.nix).
  my.sedna-failover.dnsFailover.alertEnvFile = config.my.secrets.getPath "gatus" "env";

  users = {
    groups.heartbeat = {};
    users = {
      heartbeat = {
        isSystemUser = true;
        group = "heartbeat";
      };

      root.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII6uq8nXD+QBMhXqRNywwCa/dl2VVvG/2nvkw9HEPFzn p@charon"
      ];
    };
  };

  # Keep failover/gatus domain subsets in sync with io's derived registry.
  assertions = [
    {
      assertion = lib.all (d: publicDomains ? ${d}) failoverDomains;
      message = "dnsFailover domains not in my.publicDomains registry: ${lib.concatStringsSep ", " (lib.filter (d: !(publicDomains ? ${d})) failoverDomains)}";
    }
    {
      assertion = lib.all (d: publicDomains ? ${d}) httpMonitoredDomains;
      message = "gatus-monitored domains not in my.publicDomains registry: ${lib.concatStringsSep ", " (lib.filter (d: !(publicDomains ? ${d})) httpMonitoredDomains)}";
    }
  ];
}
