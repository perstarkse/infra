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
              recommendedProxySettings = vhost.websockets;
              proxyWebsockets = vhost.websockets;
              proxyPass = targetUrl;
              extraConfig = vhost.extraConfig;
            };
          }
        ) nginxCfg.virtualHosts);
      };
    };
  };
} 