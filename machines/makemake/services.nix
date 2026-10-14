{config, ...}: {
  my = {
    # Vaultwarden password manager
    vaultwarden = {
      enable = true;
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

    # Open WebUI
    openwebui = {
      enable = true;
      port = 8080;
      dataDir = "/storage/.state/openwebui";
      # Digest-pinned image: autoUpdate's `podman pull <sha256>` is a no-op,
      # yet the timer would restart the container weekly for zero change.
      # Bump the digest explicitly to update.
      image = "ghcr.io/open-webui/open-webui@sha256:6a773e5c3a246b65cbe74ce942b294292c0e5f81c138f703d111bc162f7d7c3d";
      autoUpdate = false;
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
    };

    # Minne SaaS configuration
    minne-saas = {
      enable = true;
      port = 3001;

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

    # WebDAV access to Garage S3 for iPhone
    webdav-garage = {
      enable = true;
      bucket = "shared";
      endpoint = "http://10.0.0.10:3900";
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
      # Garage S3 binds the host LAN IP (no localhost listener).
      s3.endpoint = "http://10.0.0.10:3900";
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
          s3.endpoint = "http://10.0.0.10:3900";

          settings = {
            logLevel = "info";
            prettyBacktrace = true;
            numWorkers = 4;
            pollingHistoricalMonths = 36;
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
        endpoint = "http://10.0.0.10:3900";
        region = "garage";
      };
    };

    # Self-hosted Supabase + Accounted (LAN-only via io)
    supabase = {
      enable = true;
      additionalRedirectUrls = [
        "https://accounting.lan.stark.pub/auth/callback"
        "https://accounting.lan.stark.pub/api/auth/callback"
      ];
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
      # Public Resend webhook for the invoice-inbox extension; the 444 gating
      # and upstream live in the accounted module, io imports the endpoint.
      invoiceWebhook = {
        enable = true;
        domain = "invoices.stark.pub";
        public = true;
        router = {
          enable = true;
          targets = ["io"];
        };
      };
    };

    accounted-ocr = {
      enable = true;
    };

    signal-cli.enable = true;

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
  };

  services.deleterr.enable = true;

  services.paperless.settings = {
    # Consume dir is an rclone/FUSE mount from Garage S3; use polling instead of inotify.
    PAPERLESS_CONSUMER_POLLING = 30;
    PAPERLESS_CONSUMER_RECURSIVE = true;
  };
}
