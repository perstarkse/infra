{
  ctx,
  config,
  lib,
  pkgs,
  ...
}: {
  # The io router DNAT-hijacks outbound :53 to its own resolver, which splits
  # mail.stark.pub -> 10.0.0.10 and caches NODATA for _acme-challenge.* per
  # stark.pub SOA (1800s). lego's DNS-01 propagation check therefore never sees
  # the freshly-created TXT within its 2m window and the nightly renewal fails.
  # Skip lego's own check and rely on Let's Encrypt validating against the real
  # authoritative NSs over the public internet.
  security.acme.certs."mail.stark.pub".extraLegoFlags = ["--dns.propagation-wait=120s"];

  # Clan-core's networking module sets systemd.network.wait-online.enable =
  # false (masking systemd-networkd-wait-online), so network-online.target
  # fired ~8s before enp1s0 got its DHCP lease and every unit gated on it (garage provisioners, restic garage bootstraps,
  # attic bootstrap) or binding 10.0.0.10 (nginx, atuin) failed on every boot.
  # Pin the wait to the primary NIC only: --operational-state=degraded is the
  # state the link reaches once its address is configured (same pattern as the
  # router's wait-online in modules/system/router/network.nix).
  systemd.network.wait-online = {
    enable = lib.mkForce true;
    timeout = 30;
    extraArgs = ["--interface=enp1s0" "--operational-state=degraded"];
  };

  my = {
    attic-cache.server = {
      enable = true;
      retentionPeriod = "1 months";
    };

    backupFailureNtfy = {
      enable = true;
      url = "https://ntfy.lan.stark.pub/backup-alerts";
      tokenFile = config.my.secrets.getPath "ntfy" "backup-token";
    };

    # Garage S3-compatible storage (clustered with io)
    garage = {
      enable = true;
      metaDir = "/var/lib/garage/meta";
      replicationMode = 2;
      rpcPublicAddr = "10.0.0.10:3901";
      bindAddress = "10.0.0.10";
      zone = "makemake";
    };

    storage-alerts = {
      enable = true;
      mounts = [
        "/mnt/18tb"
        "/mnt/4tb"
        "/storage"
      ];
      mdadm.enable = true;
      ntfy = {
        serverUrl = "https://ntfy.lan.stark.pub";
        topic = "storage-alerts";
        tokenFile = config.my.secrets.getPath "ntfy" "storage-token";
        tags = ["warning" "floppy_disk" "makemake"];
      };
    };

    # Backups configuration
    backups = let
      mkB2 = path: {
        enable = true;
        inherit path;
        frequency = "daily";
        backend = {
          type = "b2";
          bucket = null;
          lifecycleKeepPriorVersionsDays = 30;
        };
      };
    in {
      accounted = mkB2 config.my.accounted.dataDir;
      minne-saas = mkB2 config.my.minne-saas.dataDir;
      vaultwarden = mkB2 config.my.vaultwarden.backupDir;

      # RocksDB file-level backup: surreal export over ws is unsupported on this arch.
      surrealdb = mkB2 config.my.surrealdb.dataDir;
      surrealdb-saas = mkB2 config.my.minne-saas.surrealdb.dataDir;

      nous =
        (mkB2 config.my.nous.dataDir)
        // {
          # The pg_dump artifact lives inside the restic data dir and MUST be
          # snapshotted: it is the only DB coverage this job has. Prepare runs
          # to completion before restic scans (same unit, no mid-write race),
          # and restic dedups an unchanged dump to ~0 bytes per snapshot.
          backupPrepareCommand = ''
            ${pkgs.sudo}/bin/sudo -u nous \
              ${pkgs.postgresql}/bin/pg_dump -Fc -f ${config.my.nous.dataDir}/nous_prod.dump nous_prod
          '';
          backupCleanupCommand = ''
            rm -f ${config.my.nous.dataDir}/nous_prod.dump
          '';
        };

      openwebui =
        (mkB2 config.my.openwebui.dataDir)
        // {
          # Most of the dataDir is cache/ (HuggingFace model weights + ephemeral
          # generations) — regenerable, worthless in a backup. User state is
          # webui.db + vector_db + uploads (~200M).
          exclude = ["${config.my.openwebui.dataDir}/cache"];
        };

      # Personal agent state: sessions, session DB, memory, skills, cron store,
      # mcp-tokens, config.yaml, workspace. One directory, one job — the agent
      # writes nothing durable outside it (see modules/system/hermes.nix).
      # Scoped to HERMES_HOME and the workspace, NOT the whole stateDir: since
      # Phase D the stateDir IS /home/agent, so backing it up wholesale would
      # sweep ~/.pi, ~/.cache and every other cache into the repo on top of
      # what the gateway actually owns.
      hermes =
        (mkB2 "${config.my.hermes.stateDir}/.hermes")
        // {
          # The session DB is SQLite and live-written: a raw restic copy of a
          # torn database is worse than no copy. Snapshot a consistent .backup
          # first, inside the snapshotted path — same shape as the pg_dump
          # prep this block already does for nous, paperless and politikerstod.
          #
          # The [ -f ] guard is load-bearing: `sqlite3 missing.db ".backup ..."`
          # exits 0 and CREATES the source file, so without it a restic run
          # before the agent's first launch would leave a 0-byte root-owned
          # state.db that hermes (running as its own user) cannot then open.
          backupPrepareCommand = ''
            if [ -f ${config.my.hermes.stateDir}/.hermes/state.db ]; then
              install -d -m 0700 ${config.my.hermes.stateDir}/.hermes/.restic-prep
              ${pkgs.sqlite}/bin/sqlite3 ${config.my.hermes.stateDir}/.hermes/state.db \
                ".backup '${config.my.hermes.stateDir}/.hermes/.restic-prep/state.db'"
            fi
          '';
          backupCleanupCommand = "rm -rf ${config.my.hermes.stateDir}/.hermes/.restic-prep";
          # $HERMES_HOME/.env is regenerated from the hermes-env generator on
          # every activation: the generator is the source of truth, so keys
          # never enter a backup repo. Same for the installed himalaya
          # config.toml (re-installed from hermes-mail on activation AND on
          # rotation — a backup copy would hold live IMAP passwords).
          #
          # The LIVE .hermes/state.db* is deliberately NOT excluded: it may be
          # torn, but .restic-prep/state.db in the same snapshot is the
          # consistent copy, and a restore that only recovered the prep would
          # lose every session taken before the first restic run. If a restore
          # ever reports a corrupt state.db, replace it with the .restic-prep
          # copy from the same snapshot.
          # The himalaya config.toml no longer needs excluding: it lives at
          # ~/.config/himalaya/config.toml, outside HERMES_HOME, so it is not in
          # this snapshot at all.
          exclude = ["${config.my.hermes.stateDir}/.hermes/.env"];
        };

      hermes-workspace = (mkB2 "${config.my.hermes.stateDir}/workspace") // {};

      paperless = {
        enable = true;
        path = config.my.paperless.dataDir;
        frequency = "daily";
        # Documents are the most irreplaceable data on this box; keep a copy
        # in Garage (same-house replication) and offsite on B2.
        backends = {
          garage = {
            type = "garage-s3";
          };
          b2 = {
            type = "b2";
            lifecycleKeepPriorVersionsDays = 30;
          };
        };
        restore.backend = "garage";
        # The pg_dump artifact lives inside the restic data dir and MUST be
        # snapshotted: it is the only DB coverage this job has. Prepare runs
        # to completion before restic scans (same unit, no mid-write race),
        # and restic dedups an unchanged dump to ~0 bytes per snapshot.
        backupPrepareCommand = ''
          PGPASSWORD=$(cat ${config.my.secrets.getPath "db-passwords" "paperless"}) \
          ${pkgs.postgresql}/bin/pg_dump \
            -h 192.168.100.22 -U paperless -Fc -f ${config.my.paperless.dataDir}/paperless.dump paperless
        '';
        backupCleanupCommand = ''
          rm -f ${config.my.paperless.dataDir}/paperless.dump
        '';
      };

      politikerstod-lekeberg =
        (mkB2 config.my.politikerstod.instances.lekeberg.dataDir)
        // {
          # The pg_dump artifact lives inside the restic data dir and MUST be
          # snapshotted: it is the only DB coverage this job has. Prepare runs
          # to completion before restic scans (same unit, no mid-write race),
          # and restic dedups an unchanged dump to ~0 bytes per snapshot.
          backupPrepareCommand = ''
            PGPASSWORD=$(cat ${config.my.secrets.getPath "db-passwords" "politikerstod"}) \
              ${pkgs.postgresql}/bin/pg_dump \
              -h 192.168.100.12 -U politikerstod -Fc \
              -f ${config.my.politikerstod.instances.lekeberg.dataDir}/politikerstod.dump \
              politikerstod_prod
          '';
          backupCleanupCommand = ''
            rm -f ${config.my.politikerstod.instances.lekeberg.dataDir}/politikerstod.dump
          '';
          exclude = [
            "${config.my.politikerstod.instances.lekeberg.dataDir}/fastembed_cache"
          ];
        };
    };
  };

  services.indicator-alert-daemon = {
    enable = true;
    intervalType = "1wk";
    pollFrequency = 86400;
    tickers = [
      {
        symbol = "ETH-USD";
        intervalType = "1d";
        indicators = [
          {
            type = "rsi";
            threshold = 30.0;
            period = 14;
          }
          {
            type = "rsi";
            threshold = 70.0;
            period = 14;
            direction = "above";
          }
        ];
      }
      {
        symbol = "BOTZ";
        indicators = [
          {
            type = "rsi";
            threshold = 30.0;
            period = 14;
          }
          {
            type = "rsi";
            threshold = 70.0;
            period = 14;
            direction = "above";
          }
        ];
      }
      {
        symbol = "SEKEUR=X";
        indicators = [
          {
            type = "rsi";
            threshold = 30.0;
            period = 14;
          }
          {
            type = "rsi";
            threshold = 70.0;
            period = 14;
            direction = "above";
          }
        ];
      }
    ];
  };

  environment.systemPackages = with pkgs; [
    mergerfs
    unrar
  ];

  programs.fuse.userAllowOther = true;

  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      function unrar-dirs --description "Unrar files in specified directories"
        for dir in $argv
          if test -d "$dir"
            echo "Processing $dir..."
            pushd "$dir"
            if test (count (find . -maxdepth 1 -name "*.rar")) -gt 0
              ${pkgs.unrar}/bin/unrar e -o+ *.rar
            else
              echo "No rar files found in $dir"
            end
            popd
          else
            echo "Directory $dir does not exist"
          end
        end
      end
    '';
  };

  # Centralized logging to router for fail2ban
  # Mail brute-force protection: SMTP/IMAP terminate on makemake, so the
  # postfix/dovecot jails run here against the local journal (the router's
  # copies of these jails read forwarded remote journals and never fire).
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "30m";
    ignoreIP = [
      "127.0.0.0/8"
      "::1"
      # Fleet peers must never be banned. 2026-10-11: charon (10.0.0.15)
      # ate a 30m sshd ban from my own `ssh agent@makemake.lan` attempts
      # with the wrong local key — every LAN host refused, not just SSH —
      # and the mesh died with it. fail2ban's stock iptables action drops
      # all traffic from the banned IP, not just port 22.
      "10.0.0.1"
      "10.0.0.10"
      "10.0.0.15"
    ];
    jails = {
      postfix = {
        settings = {
          enabled = true;
          filter = "postfix";
          backend = "systemd";
          journalmatch = "_SYSTEMD_UNIT=postfix.service";
          maxretry = 5;
          findtime = "10m";
          bantime = "30m";
        };
      };
      dovecot = {
        settings = {
          enabled = true;
          filter = "dovecot";
          backend = "systemd";
          journalmatch = "_SYSTEMD_UNIT=dovecot.service";
          maxretry = 5;
          findtime = "10m";
          bantime = "30m";
        };
      };
    };
  };

  # dovecot 2.3 logs via journald as "imap-login: Login aborted: ... (auth failed,
  # N attempts ...) ... rip=<HOST>", which the stock fail2ban dovecot filter
  # (written for the syslog form) does not match.
  environment.etc."fail2ban/filter.d/dovecot.local".text = ''
    [Definition]
    failregex = \(auth failed, [0-9]+ attempts in [0-9]+ secs\).*rip=<HOST>
    ignoreregex =
  '';

  # indicator-alert-daemon publishes to a write-protected ntfy topic; the app
  # has no auth support, so wrap its config: ntfy accepts the token in the
  # ?auth= query param as base64url("Bearer <token>"), resolved at runtime from
  # the secret (never baked into the store).
  systemd.services.indicator-alert-daemon = let
    iad = config.services.indicator-alert-daemon;
    iadFmt = pkgs.formats.json {};
    iadToken = config.my.secrets.getPath "ntfy" "indicator-token";
    iadBin = ctx.inputs.indicator-alert-daemon.packages.${pkgs.stdenv.hostPlatform.system}.default;
    iadConfig = iadFmt.generate "indicator-alert-daemon.json" (
      {
        ntfy_url = "https://ntfy.lan.stark.pub/indicator-alerts";
        interval_type = iad.intervalType;
        frequency_seconds = iad.pollFrequency;
        ticker_delay_ms = iad.tickerDelayMs;
        tickers = map (t:
          {
            inherit (t) symbol indicators;
          }
          // lib.optionalAttrs (t.intervalType != null) {interval_type = t.intervalType;})
        iad.tickers;
      }
      // lib.optionalAttrs (iad.dbPath != null) {db_path = iad.dbPath;}
    );
  in {
    serviceConfig = {
      ExecStart = lib.mkForce (pkgs.writeShellScript "indicator-alert-daemon-tokenized" ''
        set -euo pipefail
        token=$(cat ${iadToken})
        auth=$(printf 'Bearer %s' "$token" | ${pkgs.coreutils}/bin/base64 | ${pkgs.coreutils}/bin/tr '+/' '-_' | ${pkgs.coreutils}/bin/tr -d '=\n')
        # StateDirectory is writable under ProtectSystem=strict (/run is not)
        ${pkgs.jq}/bin/jq --arg u "https://ntfy.lan.stark.pub/indicator-alerts?auth=$auth" '.ntfy_url = $u' ${iadConfig} > /var/lib/indicator-alert-daemon/config.json
        exec ${iadBin}/bin/indicator-alert-daemon --config /var/lib/indicator-alert-daemon/config.json
      '');
      DynamicUser = lib.mkForce false;
    };
  };

  # The daemon reads the ntfy token only at startup: restart it when the
  # token file actually changes on disk (restartTriggers on /run/secrets
  # paths are inert strings that never fire — see mosquitto.nix).
  systemd.paths.indicator-token-rotation = {
    description = "Restart indicator-alert-daemon when its ntfy token rotates";
    wantedBy = ["multi-user.target"];
    pathConfig = {
      PathChanged = [(config.my.secrets.getPath "ntfy" "indicator-token")];
      Unit = "indicator-token-rotation-restart.service";
    };
  };

  systemd.services.indicator-token-rotation-restart = {
    description = "Restart indicator-alert-daemon after token rotation";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl try-restart indicator-alert-daemon.service";
    };
  };
}
