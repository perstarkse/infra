{
  config.flake.nixosModules.router-security = {
    lib,
    config,
    ...
  }: let
    inherit (lib) mkEnableOption mkOption types mkIf mkMerge optionalAttrs;
    cfg = config.my.router;
    secCfg = cfg.security;
    f2bCfg = secCfg.fail2ban;
    jrCfg = secCfg.journalReceiver;
    helpers = config.routerHelpers or (throw "routerHelpers not defined — is the router module loaded?");
    internalCidrs = map (segment: segment.subnetCidr) (helpers.segments or []);
    wgCfg = cfg.wireguard or {};
    wgSubnet = wgCfg.subnet or "10.6.0";
    wgCidr = "${wgSubnet}.0/${toString (wgCfg.cidrPrefix or 24)}";
    routerIp = helpers.primaryRouterIp;

    # Compute all IPs to ignore (never ban)
    autoIgnoreIPs =
      [
        "127.0.0.0/8"
        "::1"
      ]
      ++ internalCidrs
      ++ lib.optionals (wgCfg.enable or false) [wgCidr];

    allIgnoreIPs = autoIgnoreIPs ++ f2bCfg.ignoreIPs;

    # Journal remote log directory
    journalLogDir = "/var/log/journal/remote";

    enabled = cfg.enable && secCfg.enable;
    # The journal receiver itself binds loopback only; the LAN-facing endpoint
    # is nginx (port jrCfg.port) with client-certificate authentication, because
    # systemd-journal-remote in this nixpkgs build has client-cert verification
    # compiled out (HAVE_GNUTLS off — "Certificate checking disabled").
    journalReceiverPorts = lib.optionals (enabled && jrCfg.enable) [
      {
        access = "admin";
        protocol = "tcp";
        inherit (jrCfg) port;
      }
    ];
  in {
    options.my.router.security = {
      enable = mkEnableOption "router security features (Fail2Ban)";

      fail2ban = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable Fail2Ban intrusion prevention";
        };

        banTime = mkOption {
          type = types.str;
          default = "10m";
          description = "Default ban duration";
        };

        findTime = mkOption {
          type = types.str;
          default = "10m";
          description = "Time window for counting failures";
        };

        maxRetry = mkOption {
          type = types.int;
          default = 5;
          description = "Number of failures before banning";
        };

        ignoreIPs = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Additional IPs/CIDRs to never ban (LAN and WireGuard are auto-added)";
        };

        jails = {
          sshd = {
            enable = mkOption {
              type = types.bool;
              default = true;
              description = "Enable SSH brute-force protection";
            };
            maxRetry = mkOption {
              type = types.nullOr types.int;
              default = null;
              description = "Override max retry for SSH jail";
            };
          };

          nginx = {
            urlProbe = {
              enable = mkOption {
                type = types.bool;
                default = true;
                description = "Block scanners probing for wp-admin, .env, etc.";
              };
              maxRetry = mkOption {
                type = types.int;
                default = 3;
                description = "Failures before ban (scanners are aggressive)";
              };
            };
            botsearch = {
              enable = mkOption {
                type = types.bool;
                default = true;
                description = "Block bad bots/crawlers";
              };
              maxRetry = mkOption {
                type = types.int;
                default = 5;
                description = "Failures before ban";
              };
            };
            httpAuth = {
              enable = mkOption {
                type = types.bool;
                default = false;
                description = "Block HTTP Basic auth failures";
              };
            };
          };

          mail = {
            postfix = {
              enable = mkOption {
                type = types.bool;
                default = false;
                description = "Block SMTP auth failures (requires journal forwarding)";
              };
            };
            dovecot = {
              enable = mkOption {
                type = types.bool;
                default = false;
                description = "Block IMAP auth failures (requires journal forwarding)";
              };
            };
          };
        };
      };

      journalReceiver = {
        enable = mkEnableOption "systemd-journal-remote receiver for centralized logging";

        listenAddress = mkOption {
          type = types.str;
          default = routerIp;
          description = "Address to bind for incoming journal streams";
        };

        port = mkOption {
          type = types.int;
          default = 19532;
          description = "Port for journal-remote HTTP receiver";
        };
      };
    };

    config = mkIf enabled (mkMerge [
      {
        my.router.internalServicePorts = journalReceiverPorts;
      }
      # Fail2Ban configuration
      (mkIf f2bCfg.enable {
        services.fail2ban = {
          enable = true;
          maxretry = f2bCfg.maxRetry;
          bantime = f2bCfg.banTime;
          ignoreIP = allIgnoreIPs;

          # Use nftables for banning (compatible with router firewall)
          banaction = "nftables-allports";
          banaction-allports = "nftables-allports";

          # Jail configurations
          jails = mkMerge [
            # SSH jail
            (optionalAttrs f2bCfg.jails.sshd.enable {
              sshd.settings = {
                enabled = true;
                filter = "sshd";
                backend = "systemd";
                maxretry =
                  if (f2bCfg.jails.sshd.maxRetry != null)
                  then f2bCfg.jails.sshd.maxRetry
                  else f2bCfg.maxRetry;
                findtime = f2bCfg.findTime;
                bantime = f2bCfg.banTime;
              };
            })

            # Nginx URL probe jail (scanners)
            (optionalAttrs f2bCfg.jails.nginx.urlProbe.enable {
              nginx-url-probe.settings = {
                enabled = true;
                filter = "nginx-url-probe";
                logpath = "/var/log/nginx/access.log";
                backend = "auto";
                maxretry = f2bCfg.jails.nginx.urlProbe.maxRetry;
                findtime = f2bCfg.findTime;
                bantime = f2bCfg.banTime;
              };
            })

            # Nginx botsearch jail
            (optionalAttrs f2bCfg.jails.nginx.botsearch.enable {
              nginx-botsearch.settings = {
                enabled = true;
                filter = "nginx-botsearch";
                logpath = "/var/log/nginx/access.log";
                backend = "auto";
                maxretry = f2bCfg.jails.nginx.botsearch.maxRetry;
                findtime = f2bCfg.findTime;
                bantime = f2bCfg.banTime;
              };
            })

            # Nginx HTTP auth jail
            (optionalAttrs f2bCfg.jails.nginx.httpAuth.enable {
              nginx-http-auth.settings = {
                enabled = true;
                filter = "nginx-http-auth";
                logpath = "/var/log/nginx/error.log";
                backend = "auto";
                maxretry = f2bCfg.maxRetry;
                findtime = f2bCfg.findTime;
                bantime = f2bCfg.banTime;
              };
            })

            # Postfix jail (for forwarded mail logs)
            (optionalAttrs f2bCfg.jails.mail.postfix.enable {
              postfix.settings = {
                enabled = true;
                filter = "postfix";
                logpath = "${journalLogDir}/*.journal";
                backend = "systemd";
                maxretry = f2bCfg.maxRetry;
                findtime = f2bCfg.findTime;
                bantime = f2bCfg.banTime;
              };
            })

            # Dovecot jail (for forwarded mail logs)
            (optionalAttrs f2bCfg.jails.mail.dovecot.enable {
              dovecot.settings = {
                enabled = true;
                filter = "dovecot";
                logpath = "${journalLogDir}/*.journal";
                backend = "systemd";
                maxretry = f2bCfg.maxRetry;
                findtime = f2bCfg.findTime;
                bantime = f2bCfg.banTime;
              };
            })
          ];
        };

        # Custom filter definitions
        environment.etc = {
          # Nginx URL probe filter - catches scanners looking for common vulnerabilities
          "fail2ban/filter.d/nginx-url-probe.local".text = ''
            [Definition]
            # Detect probes for common vulnerable paths
            failregex = ^<HOST> .* "(GET|POST|HEAD) /(wp-|wordpress|admin|phpmyadmin|pma|\.env|\.git|\.aws|config|backup|cgi-bin|shell|\.well-known/security\.txt|xmlrpc\.php|boaform|\.dll|\.asp|\.cfm).*" (400|403|404|444)
                        ^<HOST> .* ".*\\x[0-9a-fA-F]{2}.*" (400|403|404|444)
                        ^<HOST> .* "(GET|POST) .*(union.*select|concat.*\(|benchmark\(|sleep\().*" (400|403|404|444)
                        ^<HOST> .* "(GET|POST|HEAD) /(\.\.\/|\.\.\\|%%2e%%2e).*" (400|403|404|444)

            ignoreregex =

            # Use datepattern for nginx combined log format
            datepattern = {^LN-BEG}%%ExY(?P<_sep>[-/.])%%m(?P=_sep)%%d[T ]%%H:%%M:%%S(?:[.,]%%f)?(?:\s*%%z)?
                          ^[^\[]*\[({DATE})
                          {^LN-BEG}
          '';

          # Override nginx-botsearch to be more aggressive
          "fail2ban/filter.d/nginx-botsearch.local".text = ''
            [Definition]
            # Bad bot detection based on user agent and path patterns
            # (the invoices webhook path is excluded: Resend's retrying egress
            # IPs legitimately get 401s from accounted's Svix signature check)
            failregex = ^<HOST> .* ".*(?:zgrab|Nuclei|Nmap|masscan|curl/|python-requests|Go-http-client|libwww-perl|Wget|nikto|sqlmap|nessus|nmap).*" \d+
                        ^<HOST> .* "(GET|POST) /actuator.*" (200|403|404)
                        ^<HOST> .* "(GET|POST) /api/(?!extensions/ext/invoice-inbox/inbound).*" 401

            ignoreregex =

            datepattern = {^LN-BEG}%%ExY(?P<_sep>[-/.])%%m(?P=_sep)%%d[T ]%%H:%%M:%%S(?:[.,]%%f)?(?:\s*%%z)?
                          ^[^\[]*\[({DATE})
                          {^LN-BEG}
          '';
        };

        # Ensure nginx logs to file for fail2ban (in addition to journal)
        services.nginx.appendHttpConfig = ''
          # Logging for fail2ban
          access_log /var/log/nginx/access.log combined;
          error_log /var/log/nginx/error.log;
        '';

        # Create nginx log directory
        systemd.tmpfiles.rules = [
          "d /var/log/nginx 0755 nginx nginx - -"
        ];
      })

      # Journal receiver configuration.
      #
      # systemd-journal-remote in this nixpkgs build cannot enforce client
      # certificates (HAVE_GNUTLS off: "Certificate checking disabled"), so
      # the receiver binds loopback only and the LAN-facing endpoint on port
      # jrCfg.port is nginx with client-certificate authentication against the
      # journal-upload CA. makemake's journal-upload presents client.pem;
      # requests without a valid client cert get HTTP 401.
      #
      # http2 off: systemd-journal-upload aborts with "Buffer space is too
      # small to write entry" / EIO when libcurl hands it a small trailing
      # read buffer under HTTP/2 (systemd#39166). nginx >= 1.25.1 enables h2
      # by default on ssl listeners, so it must be disabled per listener here.
      (mkIf jrCfg.enable {
        services.journald.remote = {
          enable = true;
          listen = "http";
          inherit (jrCfg) port;
        };

        # LAN-facing mTLS endpoint for journal uploads
        services.nginx.virtualHosts."journal-upload" = {
          listen = [
            {
              addr = "10.0.0.1";
              inherit (jrCfg) port;
              ssl = true;
            }
          ];
          serverName = "journal-upload";
          # The nixpkgs nginx module defaults http2 = true and would emit
          # "http2 on;"; nginx >= 1.25.1 also enables h2 by default on ssl
          # listeners. Both must be defeated here: see extraConfig below.
          http2 = false;
          # onlySSL: no port-80 redirect server. (A listen-less redirect would
          # bind this nginx build's default port 8000, colliding with kea's
          # control agent.) journal-upload always uses https.
          onlySSL = true;
          sslCertificate = toString (config.my.secrets.getPath "journal-upload" "server.pem");
          sslCertificateKey = toString (config.my.secrets.getPath "journal-upload" "server.key");
          sslTrustedCertificate = toString (config.my.secrets.getPath "journal-upload" "ca.pem");
          extraConfig = ''
            # http2 off (server directive, nginx >= 1.25.1): systemd-journal-upload
            # aborts with "Buffer space is too small to write entry" / EIO when
            # libcurl hands it a small trailing read buffer under HTTP/2
            # (systemd#39166); this listener must stay HTTP/1.1.
            http2 off;
            # journal-upload catch-up streams very large bodies
            client_max_body_size 0;
            ssl_client_certificate ${toString (config.my.secrets.getPath "journal-upload" "ca.pem")};
            ssl_verify_client optional;
            ssl_verify_depth 2;
          '';
          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString jrCfg.port}";
            recommendedProxySettings = true;
            extraConfig = ''
              # Require a client certificate signed by the journal-upload CA
              if ($ssl_client_verify != "SUCCESS") { return 401; }
              # Buffer the request so the upstream journal-remote gets a single
              # Content-Length (no Transfer-Encoding), which its handler
              # requires.
              proxy_request_buffering on;
              proxy_http_version 1.1;
            '';
          };
        };

        my.secrets.allowReadAccess = [
          {
            readers = ["nginx"];
            path = config.my.secrets.getPath "journal-upload" "server.key";
          }
          {
            readers = ["nginx"];
            path = config.my.secrets.getPath "journal-upload" "server.pem";
          }
          {
            readers = ["nginx"];
            path = config.my.secrets.getPath "journal-upload" "ca.pem";
          }
        ];

        # Bind journal-remote to the loopback only; the LAN-facing endpoint is
        # nginx (above). The leading "" is systemd's list-reset marker: it
        # clears the upstream unit's wildcard ListenStream=19532.
        systemd.sockets.systemd-journal-remote = {
          after = ["systemd-networkd-wait-online.service" "network-online.target"];
          wants = ["network-online.target"];
          listenStreams = lib.mkForce [
            ""
            "127.0.0.1:${toString jrCfg.port}"
          ];
        };

        # Create directory for remote journals
        systemd.tmpfiles.rules = [
          "d ${journalLogDir} 0755 systemd-journal-remote systemd-journal-remote - -"
        ];
      })
    ]);
  };
}
