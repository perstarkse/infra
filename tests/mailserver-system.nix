{
  lib,
  pkgs,
  privateMailserverModule,
  ...
}: let
  sopsStubModule = {lib, ...}: {
    options.sops = {
      defaultSopsFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
      };

      age.sshKeyPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
      };

      secrets = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
          options.path = lib.mkOption {
            type = lib.types.str;
            default = "/etc/test-secrets/${name}";
          };
        }));
        default = {};
      };
    };
  };

  backupsStubModule = {lib, ...}: {
    options.my.backups = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
    };
  };

  passwordHash = "$6$/z4n8AQl6K$kiOkBTWlZfBd7PvF5GsJ8PmPgdZsFGN1jPGZufxxr60PoR0oUsrvzm2oQiflyz5ir9fFJ.d/zKm/NgLXNUsNX/";

  mailNode = {options, ...}: let
    hasX509Option = lib.hasAttrByPath ["mailserver" "x509" "useACMEHost"] options;
  in {
    networking = {
      useNetworkd = true;
      useDHCP = false;
      firewall.enable = false;
    };

    systemd.network.enable = true;
    system.stateVersion = "25.11";

    imports = [
      privateMailserverModule
      sopsStubModule
      backupsStubModule
    ];

    mailserver =
      {
        enable = true;
      }
      // lib.optionalAttrs hasX509Option {
        x509 = {
          useACMEHost = lib.mkForce null;
          certificateFile = "/etc/mailserver/cert.pem";
          privateKeyFile = "/etc/mailserver/key.pem";
        };
      }
      // lib.optionalAttrs (!hasX509Option) {
        certificateScheme = "manual";
        certificateFile = "/etc/mailserver/cert.pem";
        keyFile = "/etc/mailserver/key.pem";
      };

    services.dovecot2 = {
      sslServerCert = lib.mkForce "/etc/mailserver/cert.pem";
      sslServerKey = lib.mkForce "/etc/mailserver/key.pem";
    };

    security.acme.certs = lib.mkForce {};

    environment.systemPackages = with pkgs; [
      iproute2
      python3
    ];

    environment.etc = {
      "test-secrets/mail/stark/per_crypt" = {
        mode = "0400";
        text = passwordHash;
      };

      "test-secrets/mail/stark/services_crypt" = {
        mode = "0400";
        text = passwordHash;
      };

      "test-secrets/mail/stark/paperless_ingest_crypt" = {
        mode = "0400";
        text = passwordHash;
      };

      "test-secrets/mail/stark/work_crypt" = {
        mode = "0400";
        text = passwordHash;
      };

      "test-secrets/mail/postfix_sasl_passwd" = {
        mode = "0400";
        text = "[mail.smtp2go.com]:465 test-user:test-password";
      };

      "test-secrets/restic/env" = {
        mode = "0400";
        text = ''
          B2_APPLICATION_KEY_ID=test
          B2_APPLICATION_KEY=test
        '';
      };

      "test-secrets/restic/mail_vault" = {
        mode = "0400";
        text = "b2:dummy:mail";
      };

      "test-secrets/restic/password" = {
        mode = "0400";
        text = "test-password";
      };

      "test-secrets/api-key-cloudflare-dns-private-infra" = {
        mode = "0400";
        text = "CLOUDFLARE_DNS_API_TOKEN=test";
      };

      "mailserver/cert.pem" = {
        mode = "0444";
        source = ./lib/mailserver-cert.pem;
      };

      "mailserver/key.pem" = {
        mode = "0400";
        source = ./lib/mailserver-key.pem;
      };
    };
  };
in {
  private-infra-mailserver = pkgs.testers.runNixOSTest {
    name = "private-infra-mailserver";
    nodes.machine = mailNode;

    testScript = ''
      start_all()

      machine.wait_for_unit("postfix.service")
      machine.wait_for_unit("dovecot.service")

      machine.wait_until_succeeds("systemctl is-active postfix.service", timeout=120)
      machine.wait_until_succeeds("systemctl is-active dovecot.service", timeout=120)

      machine.wait_until_succeeds("ss -ltn | grep -q ':465 '", timeout=120)
      machine.wait_until_succeeds("ss -ltn | grep -q ':993 '", timeout=120)

      machine.succeed("printf 'From: per@stark.pub\nTo: services@stark.pub\nSubject: private-infra-mailserver-test\n\nmailserver smoke test\n' | sendmail services@stark.pub")

      machine.wait_until_succeeds("postqueue -p | grep -q 'Mail queue is empty'", timeout=120)

      machine.succeed("python3 -c 'import imaplib,ssl; ctx=ssl._create_unverified_context(); i=imaplib.IMAP4_SSL(\"127.0.0.1\",993,ssl_context=ctx); i.login(\"services@stark.pub\",\"user1\"); i.select(\"INBOX\"); st,p=i.search(None,\"ALL\"); assert st==\"OK\",st; mids=[x for x in p[0].decode().split() if x]; assert mids,\"no messages in INBOX\"; st,d=i.fetch(mids[-1],\"(RFC822)\"); assert st==\"OK\",st; raw=d[0][1]; assert b\"private-infra-mailserver-test\" in raw; assert b\"mailserver smoke test\" in raw; i.logout()'")
    '';
  };
}
