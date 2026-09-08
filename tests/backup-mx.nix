{
  lib,
  pkgs,
  nixosModules,
  privateMailserverModule,
  ...
}: let
  testHelpers = import ./lib/test-helpers.nix {inherit lib;};

  commonNode = testHelpers.mkCommonNode {};

  # --- sops stub (mirrors tests/mailserver-system.nix) -----------------------
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

  # --- primary node: makemake-like mailserver (simple-nixos-mailserver) -------
  primaryNode = {options, ...}: let
    hasX509Option = lib.hasAttrByPath ["mailserver" "x509" "useACMEHost"] options;
  in
    lib.recursiveUpdate commonNode {
      virtualisation.vlans = [1];
      imports = [privateMailserverModule sopsStubModule backupsStubModule];

      systemd.network.networks."10-eth1" = {
        matchConfig.Name = "eth1";
        address = ["10.0.0.10/24"];
        networkConfig.ConfigureWithoutCarrier = true;
      };

      mailserver =
        {
          enable = true;
          # The private-infra module hardcodes fqdn/domains/accounts/sops keys
          # (mail.stark.pub / stark.pub). Keep them as-is (the VM never touches
          # real DNS) and stub the sops secret files under the same names.
          storage.path = "/data/mail";
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

      services.dovecot2.settings = {
        # dovecot 2.4 (nixpkgs 26.05) renamed these from sslServerCert/Key
        # to the snake_case settings.* keys.
        ssl_server_cert_file = lib.mkForce "/etc/mailserver/cert.pem";
        ssl_server_key_file = lib.mkForce "/etc/mailserver/key.pem";
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

        "test-secrets/mail/stark/skanning_crypt" = {
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

        "test-secrets/mail/stark/noreply_crypt" = {
          mode = "0400";
          text = passwordHash;
        };

        "test-secrets/mail/postfix_sasl_passwd" = {
          mode = "0400";
          text = "[mail.smtp2go.com]:465 test-user:test-password";
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

  # --- backup node: sedna-like queue-only backup MX ---------------------------
  backupNode = lib.recursiveUpdate commonNode {
    virtualisation.vlans = [1];
    imports = [nixosModules.backup-mx];

    systemd.network.networks."10-eth1" = {
      matchConfig.Name = "eth1";
      address = ["10.0.0.20/24"];
      networkConfig.ConfigureWithoutCarrier = true;
    };

    my.backupMx = {
      enable = true;
      primaryHost = "10.0.0.10";
      primaryPort = 25;
      relayDomains = ["stark.pub"];
    };

    environment.systemPackages = with pkgs; [
      python3
    ];
  };

  # Queue-watch node: breach on ANY queued message (maxDepth = 0), no SMTP
  # env so the test exercises detection + loud exit without network.
  watchNode = lib.recursiveUpdate backupNode {
    my.backupMx.queueWatch.maxDepth = 0;
  };
in {
  backup-mx-deliver-while-down = pkgs.testers.runNixOSTest {
    name = "backup-mx-deliver-while-down";
    nodes = {
      backup = backupNode;
      primary = primaryNode;
    };

    testScript = ''
      start_all()
      backup.wait_for_unit("postfix.service")
      primary.wait_for_unit("postfix.service")
      primary.wait_for_unit("dovecot.service")

      backup.wait_until_succeeds("ss -ltn | grep -q ':25 '", timeout=120)
      primary.wait_until_succeeds("ss -ltn | grep -q ':25 '", timeout=120)

      # 1. With primary up, send to backup's relay domain from an external
      #    sender (backup's own loopback, which is in mynetworks). It must be
      #    accepted and immediately forwarded to the primary.
      backup.succeed(
          "printf 'From: sender@external.test\\nTo: services@stark.pub\\nSubject: backup-mx-test\\n\\nhello\\n' | sendmail -f sender@external.test services@stark.pub"
      )
      # Mail is relayed to primary and lands in its maildir (INBOX).
      primary.wait_until_succeeds(
          "grep -rl 'backup-mx-test' /data/mail | grep -q .",
          timeout=120,
      )
      print("✓ mail delivered via primary while primary is up")

      # 2. Stop the primary; now send to the backup. It must be queued locally.
      primary.succeed("systemctl stop postfix dovecot")

      backup.succeed(
          "printf 'From: sender@external.test\\nTo: services@stark.pub\\nSubject: queued-during-outage\\n\\nhello2\\n' | sendmail -f sender@external.test services@stark.pub"
      )
      # It must be deferred (queued) on the backup while the primary is down.
      # postqueue -p shows the deferral reason (e.g. "Connection refused"), so
      # assert on the deferred spool having queued files instead.
      backup.wait_until_succeeds(
          "find /var/lib/postfix/queue/deferred -type f | grep -q .", timeout=120
      )
      print("✓ mail queued on backup while primary is down")

      # 3. Bring the primary back; force the backup to flush its queue.
      primary.succeed("systemctl start postfix dovecot")
      primary.wait_for_unit("postfix.service")
      # Force an immediate queue flush (default retry delay is too long).
      backup.succeed("postqueue -f")
      backup.wait_until_succeeds("postqueue -p | grep -q 'Mail queue is empty'", timeout=180)
      primary.wait_until_succeeds(
          "grep -rl 'queued-during-outage' /data/mail | grep -q .",
          timeout=120,
      )
      print("✓ queued mail flushed to primary on recovery")
    '';
  };

  backup-mx-no-open-relay = pkgs.testers.runNixOSTest {
    name = "backup-mx-no-open-relay";
    nodes.backup = backupNode;

    testScript = ''
      start_all()
      backup.wait_for_unit("postfix.service")
      backup.wait_until_succeeds("ss -ltn | grep -q ':25 '", timeout=120)

      # From an external (non-mynetworks) source, a foreign destination must be
      # rejected — reject_unauth_destination fires.
      r = backup.fail(
          "python3 -c \"import smtplib; s=smtplib.SMTP('127.0.0.1',25); s.sendmail('x@external.test',['y@foreign.test'],'msg')\""
      )
      print(f"✓ foreign recipient rejected: {r}")

      # A recipient in the configured relay domain must still be accepted from
      # an external source.
      backup.succeed(
          "python3 -c \"import smtplib; s=smtplib.SMTP('127.0.0.1',25); s.sendmail('x@external.test',['services@stark.pub'],'msg')\""
      )
      print("✓ relay-domain recipient accepted")
    '';
  };

  backup-mx-queue-watch = pkgs.testers.runNixOSTest {
    name = "backup-mx-queue-watch";
    nodes.backup = watchNode;

    testScript = ''
      start_all()
      backup.wait_for_unit("postfix.service")
      backup.wait_until_succeeds("ss -ltn | grep -q ':25 '", timeout=120)

      # Queue lifetime must outlast extended outages (default was 5d).
      lifetime = backup.succeed("postconf -h maximal_queue_lifetime").strip()
      print(f"maximal_queue_lifetime = '{lifetime}'")
      assert lifetime == "30d", f"expected 30d queue lifetime, got '{lifetime}'"

      # Empty queue: watch exits clean.
      backup.succeed("systemctl start backup-mx-queue-watch.service")
      status = backup.succeed("systemctl show backup-mx-queue-watch --property=ExecMainStatus --value").strip()
      assert status == "0", f"empty queue should exit 0, got {status}"
      print("✓ empty queue exits 0")

      # Queue one message (no primary behind 10.0.0.10: deferred, stays queued).
      backup.succeed(
          "printf 'From: sender@external.test\\nTo: services@stark.pub\\nSubject: queue-watch-breach\\n\\nhello\\n' | sendmail -f sender@external.test services@stark.pub"
      )
      backup.wait_until_succeeds(
          "find /var/lib/postfix/queue/deferred -type f | grep -q .", timeout=120
      )

      # Breach must fail loudly (alerting hooks onto the failed unit).
      backup.succeed("set +e; systemctl start backup-mx-queue-watch.service >/tmp/watch.out 2>&1; echo $? > /tmp/watch.code")
      assert backup.succeed("cat /tmp/watch.code").strip() != "0", "breached queue must fail loudly"
      status = backup.succeed("systemctl show backup-mx-queue-watch --property=ExecMainStatus --value").strip()
      assert status != "0", f"ExecMainStatus should be non-zero, got {status}"
      journal = backup.succeed("journalctl -u backup-mx-queue-watch --no-pager")
      assert "queue breached" in journal, f"should report the breach:\n{journal}"
      print("✓ breached queue fails loudly")

      # Retry while still breached: still loud, no duplicate state.
      backup.succeed("systemctl reset-failed backup-mx-queue-watch.service")
      backup.succeed("set +e; systemctl start backup-mx-queue-watch.service >/dev/null 2>&1; echo $? > /tmp/watch2.code")
      assert backup.succeed("cat /tmp/watch2.code").strip() != "0", "retry must still fail loudly"
      print("✓ retry still fails loudly")
    '';
  };

  backup-mx-no-local-delivery = pkgs.testers.runNixOSTest {
    name = "backup-mx-no-local-delivery";
    nodes.backup = backupNode;

    testScript = ''
      start_all()
      backup.wait_for_unit("postfix.service")
      backup.wait_until_succeeds("ss -ltn | grep -q ':25 '", timeout=120)

      # mydestination is empty: no local mailboxes exist on the backup.
      mydest = backup.succeed("postconf -h mydestination").strip()
      print(f"mydestination = '{mydest}'")
      assert mydest == "", f"mydestination should be empty, got '{mydest}'"

      # No maildir, no accounts, no dovecot.
      backup.fail("test -d /data/mail")
      backup.fail("systemctl is-active dovecot.service")
      print("✓ no local delivery configured on backup")
    '';
  };
}
