{
  ctx,
  config,
  lib,
  ...
}: {
  imports =
    (with ctx.flake.nixosModules; [
      options
      shared
      heartbeat
      remote-monitoring
      sedna-failover
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
      name = "p";
      extraSshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII6uq8nXD+QBMhXqRNywwCa/dl2VVvG/2nvkw9HEPFzn p@charon"
      ];
    };

    secrets = {
      discover = {
        enable = true;
        dir = ../../vars/generators;
        includeTags = [
          "gatus"
          "heartbeat"
          "cloudflare"
        ];
      };

      generateManifest = false;

      allowReadAccess = [
        {
          readers = ["failover-check"];
          path = config.my.secrets.getPath "api-key-cloudflare-dns" "api-token";
        }
        {
          readers = ["nginx"];
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
        heartbeatTimeoutMinutes = 5;
        skipDnsRevert = true;
        cloudflareApiTokenFile = config.my.secrets.getPath "api-key-cloudflare-dns" "api-token";

        zones = [
          {
            zone = "stark.pub";
            zoneId = "5b35b4cd4229d502a964e052f18dd650";
            domains = [
              "minne.stark.pub"
              "minne-demo.stark.pub"
              "request.stark.pub"
              "politikerstod.stark.pub"
              "orebro.politikerstod.stark.pub"
              "wake.stark.pub"
            ];
          }
          {
            zone = "nous.fyi";
            zoneId = "88916637654e3923f7669c7fd59ca76a";
            domains = ["nous.fyi"];
          }
        ];
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
            }) [
              "request.stark.pub"
              "minne.stark.pub"
              "nous.fyi"
              "politikerstod.stark.pub"
              "wake.stark.pub"
            ])
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
      listenAddress = "::";
      port = 18080;
      externalEndpointName = "io-heartbeat";
      deadmanInterval = "15m";
      deadmanAlert.description = "io heartbeat missing";
      # /var/lib/heartbeat/ via StateDirectory (outside PrivateTmp namespace)
      heartbeatTimestampFile = "/var/lib/heartbeat/last-heartbeat";
    };
  };

  services = {
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
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
    2222
  ];

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

  systemd.services.heartbeat-receiver.serviceConfig = {
    CapabilityBoundingSet = "";
    LockPersonality = true;
    MemoryDenyWriteExecute = true;
    NoNewPrivileges = true;
    PrivateDevices = true;
    PrivateTmp = true;
    StateDirectory = "heartbeat";
    StateDirectoryMode = "0755";
    ProtectClock = true;
    ProtectControlGroups = true;
    ProtectHome = true;
    ProtectHostname = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectSystem = "strict";
    RestrictAddressFamilies = [
      "AF_INET"
      "AF_INET6"
    ];
    RestrictNamespaces = true;
    RestrictRealtime = true;
    SystemCallArchitectures = "native";
    UMask = "0022";
  };
}
