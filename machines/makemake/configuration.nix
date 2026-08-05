{
  ctx,
  config,
  lib,
  pkgs,
  ...
}: {
  imports = with ctx.flake.nixosModules;
    [
      ./hardware-configuration.nix
      ./boot.nix
      options
      shared
      interception-tools
      stylix
      docker
      attic-cache
      vaultwarden
      openwebui
      surrealdb
      minne-saas
      backups
      garage
      nous
      politikerstod
      atuin-server
      atuin
      webdav-htpasswd-secret
      webdav-garage

      paperless
      storage-alerts
      wireguard-tunnels
      indicator-alert-daemon
      supabase
      accounted
      accounted-ocr
    ]
    ++ (with ctx.inputs.varsHelper.nixosModules; [default])
    ++ (with ctx.inputs.privateInfra.nixosModules; [media mailserver]);

  # The io router DNAT-hijacks outbound :53 to its own resolver, which splits
  # mail.stark.pub -> 10.0.0.10 and caches NODATA for _acme-challenge.* per
  # stark.pub SOA (1800s). lego's DNS-01 propagation check therefore never sees
  # the freshly-created TXT within its 2m window and the nightly renewal fails.
  # Skip lego's own check and rely on Let's Encrypt validating against the real
  # authoritative NSs over the public internet.
  security.acme.certs."mail.stark.pub".extraLegoFlags = ["--dns.propagation-wait=120s"];

  my = {
    attic-cache.server = {
      enable = true;
      listenAddress = "10.0.0.10";
      port = 8092;
      stateDir = "/var/lib/atticd";
      storageDir = "/storage/attic/storage";
      cacheName = "heliosphere";
      retentionPeriod = "1 months";
    };

    mainUser = {
      enable = false;
      name = "p";
    };

    stylix.enable = true;

    docker.enable = true;
    interception-tools.enable = true;

    listenNetworkAddress = "10.0.0.10";

    backupFailureNtfy = {
      enable = true;
      url = "https://ntfy.lan.stark.pub/backup-alerts";
      tokenFile = config.my.secrets.getPath "ntfy" "backup-token";
    };

    privateInfra.overseerr.endpoints = {
      enable = true;
      domain = "request.stark.pub";
      public = true;
      cloudflareProxied = true;
      router = {
        enable = true;
        targets = ["io"];
      };
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

    secrets = {
      discover = {
        enable = true;
        dir = ../../vars/generators;
        includeTags = ["makemake" "surrealdb" "b2" "minne-saas" "nous" "politikerstod" "politikerstod-lekeberg" "politikerstod-orebro" "garage" "garage-s3" "paperless" "ntfy" "attic-cache" "wireguard-tunnels" "supabase" "accounted" "journal-upload" "db-passwords"];
      };

      generateManifest = false;

      allowReadAccess = [
        {
          readers = ["nous"];
          path = config.my.secrets.getPath "nous" "env";
        }
        {
          readers = ["politikerstod-lekeberg"];
          path = config.my.secrets.getPath "politikerstod-lekeberg" "env";
        }
        {
          readers = ["politikerstod-lekeberg"];
          path = config.my.secrets.getPath "db-passwords" "politikerstod";
        }
        {
          readers = ["paperless"];
          path = config.my.secrets.getPath "db-passwords" "paperless";
        }
        {
          readers = ["root"];
          path = config.my.secrets.getPath "db-passwords" "paperless.env";
        }
        {
          readers = ["root"];
          path = config.my.secrets.getPath "journal-upload" "client.key";
        }
        {
          readers = ["root"];
          path = config.my.secrets.getPath "journal-upload" "client.pem";
        }
        {
          readers = ["root"];
          path = config.my.secrets.getPath "journal-upload" "ca.pem";
        }
        {
          readers = ["root"];
          path = config.my.secrets.getPath "ntfy" "backup-token";
        }
        {
          readers = ["root"];
          path = config.my.secrets.getPath "ntfy" "indicator-token";
        }
      ];
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
      minne-saas = mkB2 config.my.minne-saas.dataDir;
      vaultwarden = mkB2 config.my.vaultwarden.backupDir;

      # RocksDB file-level backup: surreal export over ws is unsupported on this arch.
      surrealdb = mkB2 config.my.surrealdb.dataDir;
      surrealdb-saas = mkB2 config.my.minne-saas.surrealdb.dataDir;

      nous =
        (mkB2 config.my.nous.dataDir)
        // {
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
        backupPrepareCommand = ''
          PGPASSWORD=$(cat ${config.my.secrets.getPath "db-passwords" "paperless"}) \
          ${pkgs.postgresql}/bin/pg_dump \
            -h 192.168.100.22 -U paperless -Fc -f ${config.my.paperless.dataDir}/paperless.dump paperless
        '';
        backupCleanupCommand = ''
          rm -f ${config.my.paperless.dataDir}/paperless.dump
        '';
      };
    };

    vaultwarden = {
      enable = true;
      port = 8322;
      address = "10.0.0.10";
      endpoints = {
        enable = true;
        domain = "vault.lan.stark.pub";
        useWildcard = "lanstark";
        lanOnly = true;
        router = {
          enable = true;
          targets = ["io"];
        };
      };
    };

    openwebui = {
      enable = true;
      port = 8080;
      dataDir = "/storage/.state/openwebui";
      # Digest-pinned image: autoUpdate's `podman pull <sha256>` is a no-op,
      # yet the timer would restart the container weekly for zero change.
      # Bump the digest explicitly to update.
      image = "ghcr.io/open-webui/open-webui@sha256:6a773e5c3a246b65cbe74ce942b294292c0e5f81c138f703d111bc162f7d7c3d";
      autoUpdate = false;
      updateSchedule = "weekly";
      endpoints = {
        enable = true;
        domain = "chat.stark.pub";
        lanOnly = true;
        router = {
          enable = true;
          targets = ["io"];
        };
      };
    };

    # SurrealDB configuration
    surrealdb = {
      enable = true;
      host = "127.0.0.1";
      port = 8220;
      dataDir = "/var/lib/surrealdb";
    };

    # Minne SaaS configuration
    minne-saas = {
      enable = true;
      port = 3001;
      address = "10.0.0.10";
      dataDir = "/var/lib/minne-saas";

      surrealdb = {
        host = "127.0.0.1";
        port = 8221;
        dataDir = "/var/lib/surrealdb-saas";
      };

      logLevel = "info";
      demoMode = true;
      demoAllowedMutatingPaths = [
        "/signin"
        "/gdpr/accept"
        "/gdpr/deny"
        "/waitlist"
        "/waitlist/"
      ];
      endpoints = {
        enable = true;
        domain = "minne.stark.pub";
        demoDomain = "minne-demo.stark.pub";
        public = true;
        cloudflareProxied = true;
        router = {
          enable = true;
          targets = ["io"];
        };
      };
    };

    # Garage S3-compatible storage (clustered with io)
    garage = {
      enable = true;
      dataDir = "/var/lib/garage/data";
      metaDir = "/var/lib/garage/meta";
      s3Port = 3900;
      region = "garage";
      replicationMode = 2;
      rpcPublicAddr = "10.0.0.10:3901";
      zone = "makemake";
    };

    # WebDAV access to Garage S3 for iPhone
    webdav-garage = {
      enable = true;
      bucket = "shared";
      endpoint = "http://127.0.0.1:3900";
      bindAddress = "10.0.0.10";
      port = 8081;
      htpasswdFile = config.my.secrets.getPath "webdav-htpasswd" "htpasswd";
      endpoints = {
        enable = true;
        domain = "webdav.lan.stark.pub";
        useWildcard = "lanstark";
        basicAuthSecret = {
          realm = "WebDAV";
          name = "webdav-htpasswd";
          file = "htpasswd";
        };
        router = {
          enable = true;
          targets = ["io"];
        };
      };
    };

    # Restrict WebDAV to the router's nginx only (io proxies
    # webdav.lan.stark.pub → 10.0.0.10:8081). The endpoints module emits the
    # dual-backend firewall rules (nft extraInputRules + iptables
    # extraCommands) and excludes 8081 from allowedTCPPorts.
    endpoints.services.webdav-garage.firewall.local.allowedSources = ["10.0.0.1"];

    # Nous burnout prevention app
    nous = {
      enable = true;
      port = 3002;
      address = "10.0.0.10";
      dataDir = "/var/lib/nous";
      host = "https://nous.fyi";
      logLevel = "info";
      endpoints = {
        enable = true;
        public = true;
        domain = "nous.fyi";
        cloudflareProxied = true;
        router = {
          enable = true;
          targets = ["io"];
        };
      };

      database = {
        name = "nous_prod";
        user = "nous";
      };

      s3 = {
        endpoint = "http://127.0.0.1:3900";
        bucket = "nous-backups";
        region = "garage";
      };

      smtp = {
        host = "mail-eu.smtp2go.com";
        port = 587;
      };
    };

    # Politikerstöd Service Instances
    politikerstod = {
      instances = {
        lekeberg = {
          enable = true;
          port = 5150;
          host = "https://politikerstod.stark.pub";
          openFirewall = true;
          endpoints = {
            enable = true;
            domain = "politikerstod.stark.pub";
            public = true;
            cloudflareProxied = true;
            router = {
              enable = true;
              targets = ["io"];
            };
          };

          database = {
            name = "politikerstod_prod";
            user = "politikerstod";
            host = "192.168.100.12"; # Container IP
            port = 5432;
            enableContainer = true;
            allowedHosts = ["10.0.0.15"]; # charon - remote worker
            passwordFile = config.my.secrets.getPath "db-passwords" "politikerstod";
            container = {
              name = "politikerstod-db"; # Preserve existing container data
              hostAddress = "192.168.100.10";
              localAddress = "192.168.100.12";
            };
          };

          scraper.baseUrl = "https://meetings.lekeberg.se";
          s3.bucket = "politikerstod";
          s3.prefix = "lekeberg";

          settings = {
            logLevel = "info";
            prettyBacktrace = true;
            numWorkers = 4;
            pollingHistoricalMonths = 36;
            openaiModel = "gpt-4.1-mini";
            evaluationModel = "gpt-4.1-mini";
            authAllowedEmailDomains = ["lekeberg.se"];
          };
        };

        orebro = {
          enable = false;
          port = 5151;
          host = "https://orebro.politikerstod.stark.pub";
          openFirewall = true;
          endpoints = {
            enable = true;
            domain = "orebro.politikerstod.stark.pub";
            public = true;
            cloudflareProxied = true;
            router = {
              enable = true;
              targets = ["io"];
            };
          };

          database = {
            name = "politikerstod_orebro";
            user = "politikerstod_orebro";
            host = "192.168.100.13"; # Container IP
            port = 5432;
            enableContainer = true;
            proxyPort = 5433;
            allowedHosts = ["10.0.0.15"]; # charon - remote worker
            container = {
              hostAddress = "192.168.100.11";
              localAddress = "192.168.100.13";
            };
          };

          scraper.baseUrl = "https://politiskamoten.regionorebrolan.se/";
          s3.prefix = "orebro";

          settings = {
            logLevel = "info";
            prettyBacktrace = true;
            numWorkers = 4;
            pollingHistoricalMonths = 1;
            openaiModel = "gpt-4.1-mini";
            evaluationModel = "gpt-4.1-mini";
          };
        };
      };
    };

    # Atuin Sync Server
    atuin-server = {
      enable = true;
      port = 8888;
      openFirewall = true;
      endpoints = {
        enable = true;
        domain = "atuin.lan.stark.pub";
        useWildcard = "lanstark";
        router = {
          enable = true;
          targets = ["io"];
        };
      };
    };

    # Atuin client
    atuin.enable = true;

    # Paperless-ngx document management
    paperless = {
      enable = true;
      openFirewall = true;
      port = 28981;
      address = "10.0.0.10";
      url = "https://dokument.lan.stark.pub";
      dataDir = "/var/lib/paperless";
      consumptionDir = "/var/lib/paperless/consume";
      mediaDir = "/var/lib/paperless/media";
      ocr = {
        language = "swe+eng";
        # paperless 2.20 dropped the legacy "always" value; "force" keeps
        # the same intent (OCR everything, never skip).
        mode = "force";
      };
      database = {
        name = "paperless";
        user = "paperless";
        host = "192.168.100.22";
        port = 5432;
        enableContainer = true;
        passwordFile = config.my.secrets.getPath "db-passwords" "paperless";
        passwordEnvFile = config.my.secrets.getPath "db-passwords" "paperless.env";
        container = {
          hostAddress = "192.168.100.20";
          localAddress = "192.168.100.22";
        };
      };
      tika.enable = true;
      endpoints = {
        enable = true;
        domain = "dokument.lan.stark.pub";
        useWildcard = "lanstark";
        router = {
          enable = true;
          targets = ["io"];
        };
      };
      s3Consumption = {
        enable = true;
        bucket = "paperless-consume";
        endpoint = "http://127.0.0.1:3900";
        region = "garage";
      };
    };

    wireguard-tunnels = {
      enable = true;
      tunnels = {
        genome-worktree-zenith = {
          activationPolicy = "manual";
        };
      };
    };

    # Self-hosted Supabase + Accounted (LAN-only via io)
    supabase = {
      enable = true;
      siteUrl = "https://accounting.lan.stark.pub";
      additionalRedirectUrls = [
        "https://accounting.lan.stark.pub/auth/callback"
        "https://accounting.lan.stark.pub/api/auth/callback"
      ];
      smtp = {
        host = "mail-eu.smtp2go.com";
        port = 587;
        adminEmail = "noreply@stark.pub";
        senderName = "Accounted";
      };
      storage = {
        endpoint = "http://10.0.0.10:3900";
        bucket = "supabase";
      };
      endpoints = {
        enable = true;
        domain = "supabase.lan.stark.pub";
        useWildcard = "lanstark";
        lanOnly = true;
        router = {
          enable = true;
          targets = ["io"];
        };
      };
    };

    accounted = {
      enable = true;
      port = 3050;
      address = "10.0.0.10";
      supabaseUrl = "https://supabase.lan.stark.pub";
      endpoints = {
        enable = true;
        domain = "accounting.lan.stark.pub";
        useWildcard = "lanstark";
        lanOnly = true;
        # Next.js auth sends large Set-Cookie headers; increase nginx proxy
        # buffers to avoid "upstream sent too big header" 502 errors.
        extraConfig = ''
          proxy_buffer_size 16k;
          proxy_buffers 8 16k;
          proxy_busy_buffers_size 32k;
        '';
        router = {
          enable = true;
          targets = ["io"];
        };
      };
    };

    accounted-ocr = {
      enable = true;
      backend = "local";
      llm.ollama = {
        model = "qwen2.5:3b"; # 3B is snappy on N100; try 7B if you have patience
        igpu = true; # Uses Intel UHD Graphics via Vulkan
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

  time.timeZone = "Europe/Stockholm";

  services.deleterr.enable = true;

  services.paperless.settings = {
    # Consume dir is an rclone/FUSE mount from Garage S3; use polling instead of inotify.
    PAPERLESS_CONSUMER_POLLING = 30;
    PAPERLESS_CONSUMER_RECURSIVE = true;
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

  networking = {
    firewall.allowedTCPPorts = [8088];
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

  # Centralized logging to router for fail2ban — mTLS with the router's
  # journal-remote listener (client cert signed by journal-upload ca.pem).
  services.journald.upload = {
    enable = true;
    settings = {
      Upload = {
        URL = "https://10.0.0.1:19532";
        ServerKeyFile = toString (config.my.secrets.getPath "journal-upload" "client.key");
        ServerCertificateFile = toString (config.my.secrets.getPath "journal-upload" "client.pem");
        TrustedCertificateFile = toString (config.my.secrets.getPath "journal-upload" "ca.pem");
      };
    };
  };

  # The mTLS client key is root-only; run the uploader as root (the module
  # defaults to a DynamicUser that cannot read it).
  systemd.services.systemd-journal-upload.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = lib.mkForce "root";
  };

  # indicator-alert-daemon publishes to a write-protected ntfy topic; the app
  # has no auth support, so wrap its config: ntfy accepts the token in the
  # ?auth= query param as base64url("Bearer <token>"), resolved at runtime from
  # the secret (never baked into the store).
  systemd.services.indicator-alert-daemon = let
    iad = config.services.indicator-alert-daemon;
    iadFmt = pkgs.formats.json {};
    iadToken = config.my.secrets.getPath "ntfy" "indicator-token";
    iadBin = ctx.inputs.indicator-alert-daemon.packages.${pkgs.system}.default;
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
}
