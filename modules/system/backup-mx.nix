_: {
  config.flake.nixosModules.backup-mx = {
    config,
    lib,
    ...
  }: let
    cfg = config.my.backupMx;
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
    ]);
  };
}
