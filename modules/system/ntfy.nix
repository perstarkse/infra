_: {
  config.flake.nixosModules.ntfy = {
    config,
    lib,
    mkStandardExposureOptions,
    ...
  }: let
    cfg = config.my.ntfy;
    envFile =
      if cfg.secretName == null
      then cfg.environmentFile
      else config.my.secrets.getPath cfg.secretName "env";
  in {
    options.my.ntfy = {
      enable = lib.mkEnableOption "Enable ntfy push notification server";

      port = lib.mkOption {
        type = lib.types.port;
        default = 2586;
        description = "Port for ntfy to listen on";
      };

      address = lib.mkOption {
        type = lib.types.str;
        default = config.my.listenNetworkAddress;
        description = "Address for ntfy to bind to";
      };

      baseUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://ntfy.stark.pub";
        description = "Public base URL for ntfy";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Open firewall for the ntfy port";
      };

      environmentFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Optional environment file for ntfy secrets";
      };

      secretName = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "ntfy";
        description = "Clan vars secret generator name that provides ntfy env config.";
      };

      settings = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = "Additional ntfy settings merged into services.ntfy-sh.settings";
      };

      exposure =
        mkStandardExposureOptions {
          subject = "ntfy";
          visibility = "internal";
          withExtraConfigDefault = ''
            client_max_body_size 0;
            proxy_buffering off;
            proxy_request_buffering off;
            proxy_read_timeout 1h;
            proxy_send_timeout 1h;
          '';
        }
        // {
          domain = lib.mkOption {
            type = lib.types.str;
            default = lib.removePrefix "https://" (lib.removePrefix "http://" cfg.baseUrl);
            description = "Domain used for generated ntfy reverse proxy and DNS exposure.";
          };
        };
    };

    config = lib.mkIf cfg.enable {
      my.secrets.allowReadAccess = lib.mkIf (envFile != null) [
        {
          readers = ["ntfy-sh"];
          path = envFile;
        }
      ];

      services.ntfy-sh = {
        enable = true;
        environmentFile = envFile;
        settings =
          {
            base-url = cfg.baseUrl;
            listen-http = "${cfg.address}:${toString cfg.port}";
          }
          // cfg.settings;
      };

      my.exposure.services.ntfy = lib.mkIf cfg.exposure.enable {
        upstream = {
          host = cfg.address;
          inherit (cfg) port;
        };
        http.virtualHosts = [
          {
            inherit (cfg.exposure) domain;
            inherit (cfg.exposure) lanOnly useWildcard extraConfig;
            websockets = true;
          }
        ];
        firewall.local = {
          enable = cfg.openFirewall;
          tcp = [cfg.port];
        };
      };
    };
  };
}
