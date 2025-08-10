{
  config.flake.nixosModules.nginx = {
    lib,
    config,
    pkgs,
    ...
  }: let
    cfg = config.my.nginx;
    routerCfg = config.my.router;
    lanSubnet = routerCfg.lanSubnet;
    calculated = config.my.router.calculated;
  in {
    options.my.nginx = {
      enable = lib.mkEnableOption "Enable nginx reverse proxy";

      acmeEmail = lib.mkOption {
        type = lib.types.str;
        default = "services@stark.pub";
        description = "Email for ACME/Let's Encrypt certificates";
      };

      ddclient = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable ddclient for dynamic DNS";
        };
      };

      virtualHosts = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            domain = lib.mkOption {
              type = lib.types.str;
              description = "Domain name for the virtual host";
            };
            target = lib.mkOption {
              type = lib.types.str;
              description = "Target machine name (from router.machines) or IP:port";
            };
            port = lib.mkOption {
              type = lib.types.int;
              description = "Target port";
            };
            websockets = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable WebSocket support";
            };
            extraConfig = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Extra nginx configuration";
            };
          };
        });
        default = [];
        description = "List of virtual hosts to configure";
      };
    };

    config = lib.mkIf cfg.enable {
      security.acme = {
        acceptTerms = true;
        defaults.email = cfg.acmeEmail;
      };

      services.ddclient = lib.mkIf cfg.ddclient.enable {
        enable = true;
        package = pkgs.unstable.ddclient;
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
            # Resolve target to IP:port using precomputed machinesByName when possible
            tgt = vhost.target;
            m = calculated.machinesByName.${vhost.target} or null;
            targetIp = if lib.hasPrefix "10.0.0." tgt then
              tgt
            else if m != null then
              "${lanSubnet}.${m.ip}"
            else
              tgt;
            targetUrl = "http://${targetIp}:${toString vhost.port}";
          in
          lib.nameValuePair vhost.domain {
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

            enableACME = true;
            forceSSL = true;

            locations."/" = {
              recommendedProxySettings = vhost.websockets;
              proxyWebsockets = vhost.websockets;
              proxyPass = targetUrl;
              extraConfig = vhost.extraConfig;
            };
          }
        ) cfg.virtualHosts);
      };
    };
  };
} 