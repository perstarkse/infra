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
    helpers = config.routerHelpers or {};
    lanCidr = helpers.lanCidr or "${cfg.lan.subnet}.0/24";
    wgCfg = cfg.wireguard or {};
    wgSubnet = wgCfg.subnet or "10.6.0";
    wgCidr = "${wgSubnet}.0/${toString (wgCfg.cidrPrefix or 24)}";
    routerIp = helpers.routerIp or "${cfg.lan.subnet}.1";
    jrListenHost =
      if builtins.match ".*:.*" jrCfg.listenAddress != null && !(lib.hasPrefix "[" jrCfg.listenAddress)
      then "[${jrCfg.listenAddress}]"
      else jrCfg.listenAddress;
    jrListenStream = "${jrListenHost}:${toString jrCfg.port}";

    # Compute all IPs to ignore (never ban)
    autoIgnoreIPs =
      [
        "127.0.0.0/8"
        "::1"
        lanCidr
      ]
      ++ lib.optionals (wgCfg.enable or false) [wgCidr];

    allIgnoreIPs = autoIgnoreIPs ++ f2bCfg.ignoreIPs;

    # Journal remote log directory
    journalLogDir = "/var/log/journal/remote";

    enabled = cfg.enable && secCfg.enable;
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
            failregex = ^<HOST> .* ".*(?:zgrab|Nuclei|Nmap|masscan|curl/|python-requests|Go-http-client|libwww-perl|Wget|nikto|sqlmap|nessus|nmap).*" \d+
                        ^<HOST> .* "(GET|POST) /actuator.*" (200|403|404)
                        ^<HOST> .* "(GET|POST) /api/.*" 401

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

      # Journal receiver configuration
      (mkIf jrCfg.enable {
        # Enable journal-remote service to receive logs from other hosts
        services.journald.remote = {
          enable = true;
          listen = "http";
          inherit (jrCfg) port;
        };

        # Bind journal-remote to an explicit address+port socket
        systemd.sockets.systemd-journal-remote.listenStreams = lib.mkForce [
          ""
          jrListenStream
        ];

        # Create directory for remote journals
        systemd.tmpfiles.rules = [
          "d ${journalLogDir} 0755 systemd-journal-remote systemd-journal-remote - -"
        ];
      })
    ]);
  };
}
