{
  ctx,
  lib,
  ...
}: {
  imports =
    (with ctx.flake.nixosModules; [
      options
      shared
      heartbeat
      remote-monitoring
    ])
    ++ (with ctx.inputs.varsHelper.nixosModules; [default]);

  swapDevices = [
    {
      device = "/swapfile";
      size = 4096;
    }
  ];

  my = {
    mainUser.name = "p";

    secrets = {
      discover = {
        enable = true;
        dir = ../../vars/generators;
        includeTags = [
          "gatus"
          "heartbeat"
        ];
      };

      generateManifest = false;
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
              "chat.stark.pub"
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
      listenAddress = "::";
      port = 18080;
      externalEndpointName = "io-heartbeat";
      deadmanInterval = "25m";
      deadmanAlert.description = "io heartbeat missing";
    };
  };

  services.avahi.enable = lib.mkForce false;

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII6uq8nXD+QBMhXqRNywwCa/dl2VVvG/2nvkw9HEPFzn p@charon"
  ];
}
