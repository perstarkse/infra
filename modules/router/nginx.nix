{ lib, config, pkgs, ... }:
{
  config.flake.nixosModules.router-nginx = { lib, config, pkgs, ... }:
  let
    cfg = config.my.router;
    nginxCfg = cfg.nginx;
    helpers = config.routerHelpers or {};
    lanSubnet = helpers.lanSubnet or cfg.lan.subnet;
    machines = cfg.machines;
    enabled = cfg.enable && nginxCfg.enable;
    lanCidr = helpers.lanCidr or "${lanSubnet}.0/24";
    ulaPrefix = helpers.ulaPrefix or cfg.ipv6.ulaPrefix;
   in
  {
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

        virtualHosts = lib.listToAttrs (map (vhost:
          let
            targetIp = if lib.hasPrefix "${lanSubnet}." vhost.target then
              vhost.target
            else
              let machine = lib.findFirst (m: m.name == vhost.target) null machines;
              in if machine != null then
                "${lanSubnet}.${machine.ip}"
              else
                vhost.target;
            targetUrl = "http://${targetIp}:${toString vhost.port}";
            lanAcl = lib.optionalString (vhost.lanOnly or false) ''
              allow ${lanCidr};
              allow ${ulaPrefix}::/64;
              deny all;
            '';
            mergedExtra = lib.concatStringsSep "\n" (lib.filter (s: s != "") [ (vhost.extraConfig or "") lanAcl ]);
          in
          lib.nameValuePair vhost.domain {
            serverName = vhost.domain;
            listen = [
              { addr = "0.0.0.0"; port = 80; }
              { addr = "0.0.0.0"; port = 443; ssl = true; }
            ];
            enableACME = true;
            forceSSL = true;
            locations."/" = {
              recommendedProxySettings = true;
              proxyWebsockets = vhost.websockets;
              proxyPass = targetUrl;
              extraConfig = mergedExtra;
            };
          }
        ) nginxCfg.virtualHosts);
      };

      security.acme.certs = lib.mkMerge (map (vhost:
        let acme = vhost.acmeDns01 or null; in
        lib.optionalAttrs (acme != null) {
          "${vhost.domain}" = lib.mkMerge [
            {
              dnsProvider = acme.dnsProvider;
              group = acme.group;
              webroot = null;
            }
            (lib.optionalAttrs (acme.environmentFile != null) { environmentFile = acme.environmentFile; })
          ];
        }
      ) nginxCfg.virtualHosts);
    };
  };
} 