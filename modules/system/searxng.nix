{
  config.flake.nixosModules.searxng = {
    lib,
    config,
    pkgs,
    ...
  }: let
    cfg = config.my.searxng;
    inherit (lib) mkOption mkEnableOption types mkIf mkMerge;

    defaultEngines = [
      "duckduckgo"
      "brave"
      "wikipedia"
      "github"
      "reddit"
      "startpage"
      "qwant"
      "hackernews"
      "arch linux wiki"
      "gitlab"
      "stackoverflow"
      "nixos wiki"
    ];
  in {
    options.my.searxng = {
      enable = mkEnableOption "SearXNG metasearch engine";

      port = mkOption {
        type = types.port;
        default = 8088;
        description = "Port SearXNG listens on";
      };

      address = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Address SearXNG binds to";
      };

      instanceName = mkOption {
        type = types.str;
        default = "Heliosphere Search";
        description = "Display name for the SearXNG instance";
      };

      baseUrl = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "https://search.lan.stark.pub";
        description = "External base URL for reverse-proxied SearXNG links";
      };

      engines = {
        enable = mkOption {
          type = types.listOf types.str;
          default = defaultEngines;
          description = "List of search engines to enable";
        };

        disable = mkOption {
          type = types.listOf types.str;
          default = ["google" "bing" "yahoo" "yandex" "wikidata" "ahmia" "torch"];
          description = "List of search engines to explicitly disable";
        };
      };

      vpn = {
        enable = mkEnableOption "Route SearXNG traffic through VPN namespace";

        wireguardConfigFile = mkOption {
          type = types.str;
          description = ''
            Path to the WireGuard config file.
            Must include a DNS = ... line (required by vpn-confinement).
            Example: config.my.secrets.getPath "wireguard-tunnels-genome-worktree-zenith" "wg.conf"
          '';
        };

        accessibleFrom = mkOption {
          type = types.listOf types.str;
          default = ["10.0.0.0/24"];
          description = "Subnets allowed to reach SearXNG through the VPN namespace";
        };

        portMappings = mkOption {
          type = types.listOf (types.submodule {
            options = {
              from = mkOption {
                type = types.port;
                description = "Port on the host";
              };
              to = mkOption {
                type = types.port;
                description = "Port inside the VPN namespace";
              };
              protocol = mkOption {
                type = types.enum ["tcp" "udp" "both"];
                default = "tcp";
                description = "Transport protocol";
              };
            };
          });
          default = [
            {
              from = 8088;
              to = 8088;
            }
          ];
          description = "Port mappings from host to VPN namespace";
        };
      };
    };

    config = mkIf cfg.enable (mkMerge [
      {
        assertions = [
          {
            assertion = !cfg.vpn.enable -> cfg.address != "127.0.0.1";
            message = "my.searxng.address should not be 127.0.0.1 when VPN is disabled (nginx needs to reach it)";
          }
        ];

        networking.enableIPv6 = true;
        networking.firewall.allowedTCPPorts = [8088];

        services.searx = {
          enable = true;
          package = pkgs.searxng;
          environmentFile = config.my.secrets.getPath "searx-env" "env";
          settings = {
            use_default_settings = {
              engines.keep_only = lib.filter (name: !lib.elem name cfg.engines.disable) cfg.engines.enable;
            };
            general = {
              instance_name = cfg.instanceName;
              debug = false;
            };
            search = {
              safe_search = 0;
              autocomplete = "duckduckgo";
              default_lang = "sv";
              formats = ["html" "json" "rss"];
            };
            outgoing = {
              source_ips = ["0.0.0.0" "::"];
              enable_http2 = true;
              request_timeout = 2.0;
              max_request_timeout = 10.0;
            };
            server = {
              base_url = cfg.baseUrl;
              inherit (cfg) port;
              bind_address =
                if cfg.vpn.enable
                then "192.168.16.1"
                else cfg.address;
              secret_key = "$SEARX_SECRET_KEY";
              limiter = false;
              public_instance = false;
              image_proxy = true;
              method = "GET";
            };
            ui = {
              static_use_hash = true;
              default_theme = "simple";
              default_locale = "sv";
              theme_args.style = "auto";
            };
            preferences = {
              lock = ["autocomplete"];
            };
            enabled_plugins = [
              "Hash plugin"
              "Self Informations"
              "Tracker URL remover"
            ];
          };
        };

        my.secrets.allowReadAccess = [
          {
            readers = ["searx"];
            path = config.my.secrets.getPath "searx-env" "env";
          }
        ];
      }

      (mkIf cfg.vpn.enable {
        vpnNamespaces.sxvpn = {
          enable = true;
          inherit (cfg.vpn) wireguardConfigFile;
          inherit (cfg.vpn) accessibleFrom portMappings;
          bridgeAddress = "192.168.16.5";
          namespaceAddress = "192.168.16.1";
          openVPNPorts = [
            {
              port = 443;
              protocol = "tcp";
            }
            {
              port = 80;
              protocol = "tcp";
            }
          ];
        };
        systemd.services.searx.vpnConfinement = {
          enable = true;
          vpnNamespace = "sxvpn";
        };
      })

      {
        my.secrets.declarations = [
          (config.my.secrets.mkMachineSecret {
            name = "searx-env";
            runtimeInputs = [pkgs.openssl];
            files = {
              "env" = {mode = "0400";};
            };
            script = ''
              set -euo pipefail
              umask 077
              mkdir -p "$out"

              if [ -f "$prompts/env" ] && [ -s "$prompts/env" ]; then
                cp "$prompts/env" "$out/env"
              else
                secret_key=$(openssl rand -hex 32)
                echo "SEARX_SECRET_KEY=$secret_key" > "$out/env"
              fi

              chmod 0400 "$out/env"
            '';
            meta.tags = ["searx"];
            meta.description = "SearXNG instance secret key";
          })
        ];
      }
    ]);
  };
}
