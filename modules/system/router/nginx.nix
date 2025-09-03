{
  lib,
  config,
  pkgs,
  ...
}: {
  config.flake.nixosModules.router-nginx = {
    lib,
    config,
    pkgs,
    ...
  }: let
    cfg = config.my.router;
    nginxCfg = cfg.nginx;
    helpers = config.routerHelpers or {};
    lanSubnet = helpers.lanSubnet or cfg.lan.subnet;
    machines = cfg.machines;
    enabled = cfg.enable && nginxCfg.enable;
    lanCidr = helpers.lanCidr or "${lanSubnet}.0/24";
    ulaPrefix = helpers.ulaPrefix or cfg.ipv6.ulaPrefix;
    wgSubnet = (cfg.wireguard or {}).subnet or "10.6.0";
    wgCidr = "${wgSubnet}.0/24";
    cfNeeded = lib.any (v: (v.cloudflareOnly or false)) nginxCfg.virtualHosts;
    cfDir = "/var/lib/cloudflare-ips";
    cfAllow = "${cfDir}/allow.conf";
    cfRealip = "${cfDir}/realip.conf";
    cfGeo = "${cfDir}/edge-geo.conf";
  in {
    config = lib.mkIf enabled {
      security.acme = {
        acceptTerms = true;
        defaults.email = nginxCfg.acmeEmail;
      };

      services.ddclient = lib.mkIf nginxCfg.ddclient.enable {
        enable = true;
        package = pkgs.ddclient;
        configFile = config.my.secrets.getPath "ddclient" "ddclient.conf";
      };

      services.nginx = {
        enable = true;

        recommendedGzipSettings = true;
        recommendedOptimisation = true;
        recommendedProxySettings = true;
        recommendedTlsSettings = true;

        appendHttpConfig = lib.mkIf cfNeeded ''
          # Trust Cloudflare edges for real client IP
          include ${cfRealip};

          # Cloudflare edge membership based on socket peer ($realip_remote_addr)
          geo $realip_remote_addr $cf_edge {
            default 0;
            include ${cfGeo};
          }

          # LAN + ULA64 + WireGuard membership based on (possibly realip) $remote_addr
          geo $lan_wg {
            default 0;
            ${lanCidr} 1;
            ${ulaPrefix}::/64 1;
            ${wgCidr} 1;
          }

          # Combined access: allow if from LAN/WG, or via CF edge
          map "$lan_wg$cf_edge" $cf_access_ok {
            default 0;
            10 1;
            11 1;
            01 1;
          }
        '';

        virtualHosts = lib.listToAttrs (map (
            vhost: let
              targetIp =
                if lib.hasPrefix "${lanSubnet}." vhost.target
                then vhost.target
                else let
                  machine = lib.findFirst (m: m.name == vhost.target) null machines;
                in
                  if machine != null
                  then "${lanSubnet}.${machine.ip}"
                  else vhost.target;

              targetUrl = "http://${targetIp}:${toString vhost.port}";

              lanAllow = ''
                allow ${lanCidr};
                allow ${ulaPrefix}::/64;
                allow ${wgCidr};
              '';

              acl =
                if (vhost.cloudflareOnly or false)
                then ''
                  if ($cf_access_ok = 0) { return 403; }
                ''
                else if (vhost.lanOnly or false)
                then ''
                  ${lanAllow}
                  deny all;
                ''
                else "";

              mergedExtra =
                lib.concatStringsSep "\n"
                (lib.filter (s: s != "") [(vhost.extraConfig or "") acl]);

              # common part
              baseCfg = {
                serverName = vhost.domain;
                listen = [
                  {
                    addr = "0.0.0.0";
                    port = 80;
                  }
                  {
                    addr = "0.0.0.0";
                    port = 443;
                    ssl = true;
                  }
                ];
                locations."/" = {
                  recommendedProxySettings = true;
                  proxyWebsockets = vhost.websockets;
                  proxyPass = targetUrl;
                  extraConfig = mergedExtra;
                };
              };

              # ssl policy
              sslConfig =
                # Explicit wildcard certificate case
                if vhost.useWildcard != null
                then let
                  wc = lib.findFirst (c: c.name == vhost.useWildcard) null nginxCfg.wildcardCerts;
                in
                  if wc == null
                  then throw "nginx: unknown wildcard cert ‘‘${vhost.useWildcard}’’ for vhost ‘‘${vhost.domain}’’"
                  else {
                    enableACME = false; # don’t request per‑vhost cert
                    useACMEHost = wc.baseDomain; # reuse wildcard cert
                    forceSSL = true; # always serve HTTPS
                  }
                # Forced no-ACME/self-signed case
                else if vhost.noAcme or false
                then {
                  enableACME = false;
                  forceSSL = true;
                  sslCertificate = "/etc/ssl/certs/ssl-cert-snakeoil.pem";
                  sslCertificateKey = "/etc/ssl/private/ssl-cert-snakeoil.key";
                }
                # Default: issue ACME cert per vhost
                else {
                  enableACME = true;
                  forceSSL = true;
                };
            in
              lib.nameValuePair vhost.domain (baseCfg // sslConfig)
          )
          nginxCfg.virtualHosts);
      };

      security.acme.certs = lib.mkMerge (
        (map (
            vhost: let
              acme = vhost.acmeDns01 or null;
            in
              lib.optionalAttrs (acme != null) {
                "${vhost.domain}" =
                  {
                    dnsProvider = acme.dnsProvider;
                    group = acme.group;
                    webroot = null;
                  }
                  // lib.optionalAttrs (acme.environmentFile != null) {
                    environmentFile = acme.environmentFile;
                  };
              }
          )
          nginxCfg.virtualHosts)
        ++ (map (wc: {
            "${wc.baseDomain}" =
              {
                dnsProvider = wc.dnsProvider;
                group = wc.group;
                webroot = null;
                extraDomainNames = ["*.${wc.baseDomain}"];
              }
              // lib.optionalAttrs (wc.environmentFile != null) {
                environmentFile = wc.environmentFile;
              };
          })
          nginxCfg.wildcardCerts)
      );
      systemd.tmpfiles.rules = lib.mkIf cfNeeded [
        "d ${cfDir} 0755 root root - -"
        "f ${cfAllow} 0644 root root - -"
        "f ${cfRealip} 0644 root root - -"
        "f ${cfGeo} 0644 root root - -"
      ];

      systemd.services.cloudflare-ips-update = lib.mkIf cfNeeded {
        description = "Update Cloudflare IP snippets for nginx";
        wants = ["network-online.target"];
        after = ["network-online.target"];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.writeShellScript "cloudflare-ips-update" ''
            set -euo pipefail
            dir="${cfDir}"
            ${pkgs.coreutils}/bin/mkdir -p "$dir"
            tmp="$(${pkgs.coreutils}/bin/mktemp -d)"
            trap '${pkgs.coreutils}/bin/rm -rf "$tmp"' EXIT

            ${pkgs.curl}/bin/curl -fsS https://www.cloudflare.com/ips-v4 > "$tmp/ips-v4"
            ${pkgs.curl}/bin/curl -fsS https://www.cloudflare.com/ips-v6 > "$tmp/ips-v6"

            # Access module style allow list (kept for reference)
            {
              while IFS= read -r cidr; do [ -n "$cidr" ] && printf 'allow %s;\n' "$cidr"; done < "$tmp/ips-v4"
              while IFS= read -r cidr; do [ -n "$cidr" ] && printf 'allow %s;\n' "$cidr"; done < "$tmp/ips-v6"
            } > "$tmp/allow.conf"

            # Real IP trust
            {
              while IFS= read -r cidr; do [ -n "$cidr" ] && printf 'set_real_ip_from %s;\n' "$cidr"; done < "$tmp/ips-v4"
              while IFS= read -r cidr; do [ -n "$cidr" ] && printf 'set_real_ip_from %s;\n' "$cidr"; done < "$tmp/ips-v6"
              printf 'real_ip_header CF-Connecting-IP;\n'
              printf 'real_ip_recursive on;\n'
            } > "$tmp/realip.conf"

            # Geo include for CF edges
            {
              while IFS= read -r cidr; do [ -n "$cidr" ] && printf '%s 1;\n' "$cidr"; done < "$tmp/ips-v4"
              while IFS= read -r cidr; do [ -n "$cidr" ] && printf '%s 1;\n' "$cidr"; done < "$tmp/ips-v6"
            } > "$tmp/edge-geo.conf"

            changed=0
            for f in allow.conf realip.conf edge-geo.conf; do
              if ! ${pkgs.diffutils}/bin/cmp -s "$tmp/$f" "$dir/$f"; then
                ${pkgs.coreutils}/bin/install -m 0644 -D "$tmp/$f" "$dir/$f"
                changed=1
              fi
            done

            if [ "$changed" -eq 1 ]; then
              ${pkgs.nginx}/bin/nginx -t && ${pkgs.systemd}/bin/systemctl reload nginx || true
            fi
          ''}";
        };
        wantedBy = ["multi-user.target"];
      };

      systemd.timers.cloudflare-ips-update = lib.mkIf cfNeeded {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "5m";
          OnUnitActiveSec = "12h";
          RandomizedDelaySec = "10m";
        };
      };
    };
  };
}
