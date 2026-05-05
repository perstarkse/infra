{inputs, ...}: {
  config.flake.nixosModules.minne-saas = {
    config,
    lib,
    pkgs,
    mkStandardExposureOptions,
    ...
  }: let
    cfg = config.my.minne-saas;
  in {
    options.my.minne-saas = {
      enable = lib.mkEnableOption "Enable Minne SaaS service";

      port = lib.mkOption {
        type = lib.types.port;
        default = 3003;
        description = "Port for Minne SaaS Server to listen on";
      };

      address = lib.mkOption {
        type = lib.types.str;
        default = config.my.listenNetworkAddress;
        description = "Address for Minne SaaS Server to bind to (defaults to my.listenNetworkAddress)";
      };

      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/minne-saas";
        description = "Directory to store Minne SaaS data";
      };

      surrealdb = {
        host = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "SurrealDB host address";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 8221;
          description = "SurrealDB port";
        };

        dataDir = lib.mkOption {
          type = lib.types.path;
          default = "/var/lib/surrealdb-saas";
          description = "Directory to store SurrealDB SaaS data";
        };
      };

      logLevel = lib.mkOption {
        type = lib.types.str;
        default = "info";
        description = "Log level for Minne SaaS";
      };

      demoMode = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable demo mode (blocks mutating requests)";
      };

      demoAllowedMutatingPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "/signin"
          "/gdpr/accept"
          "/gdpr/deny"
          "/waitlist"
          "/waitlist/"
        ];
        description = "Mutating paths allowed in demo mode (mapped to DEMO_ALLOWED_MUTATING_PATHS)";
      };

      firewallTcpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [cfg.port];
        description = "Additional TCP ports to open for Minne SaaS.";
      };
      firewallUdpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [];
        description = "UDP ports to open for Minne SaaS.";
      };

      exposure =
        mkStandardExposureOptions {
          subject = "Minne SaaS";
          visibility = "public";
          withRouter = true;
        }
        // {
          demoDomain = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Optional demo redirect domain for generated Minne SaaS exposure.";
          };
        };
    };

    config = lib.mkIf cfg.enable {
      systemd = {
        services = {
          # SurrealDB SaaS service
          surrealdb-saas = {
            description = "SurrealDB SaaS - Database Server";
            wantedBy = ["multi-user.target"];
            after = ["network.target"];

            serviceConfig = {
              Type = "simple";
              User = "surrealdb";
              Group = "surrealdb";
              WorkingDirectory = cfg.surrealdb.dataDir;
              ExecStart = ''${pkgs.surrealdb}/bin/surreal start --bind ${cfg.surrealdb.host}:${toString cfg.surrealdb.port} rocksdb:${cfg.surrealdb.dataDir}/data.db'';
              Restart = "always";
              RestartSec = "10";

              EnvironmentFile = [
                (config.my.secrets.getPath "surrealdb-credentials" "credentials")
              ];
            };
          };

          # Minne SaaS Server service
          minne-saas-server = {
            description = "Minne SaaS - Server";
            wantedBy = ["multi-user.target"];
            after = ["network.target" "surrealdb-saas.service"];
            requires = ["surrealdb-saas.service"];

            serviceConfig = {
              Type = "simple";
              User = "minne-saas";
              Group = "minne-saas";
              WorkingDirectory = cfg.dataDir;
              ExecStart = pkgs.writeShellScript "start-minne-saas-server" ''
                # Bridge SURREALDB_USER (from credentials) to SURREALDB_USERNAME (expected by app)
                if [ -z "$SURREALDB_USERNAME" ] && [ -n "$SURREALDB_USER" ]; then
                  export SURREALDB_USERNAME="$SURREALDB_USER"
                fi
                # Bridge SURREALDB_PASS (if used) to SURREALDB_PASSWORD
                if [ -z "$SURREALDB_PASSWORD" ] && [ -n "$SURREALDB_PASS" ]; then
                  export SURREALDB_PASSWORD="$SURREALDB_PASS"
                fi

                exec ${inputs.saas-minne.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/saas-server
              '';
              Restart = "always";
              RestartSec = "10";

              # Basic environment variables
              Environment = [
                "SURREALDB_ADDRESS=ws://${cfg.surrealdb.host}:${toString cfg.surrealdb.port}"
                "HTTP_PORT=${toString cfg.port}"
                "RUST_LOG=${cfg.logLevel}"
                "DATA_DIR=${cfg.dataDir}"
                "DEMO_MODE=${lib.boolToString cfg.demoMode}"
                "DEMO_ALLOWED_MUTATING_PATHS=${lib.concatStringsSep "," cfg.demoAllowedMutatingPaths}"
              ];

              # Load environment file for all secrets
              EnvironmentFile = [
                (config.my.secrets.getPath "minne-saas" "env")
              ];
            };
          };

          # Minne SaaS Worker service
          minne-saas-worker = {
            description = "Minne SaaS - Worker";
            wantedBy = ["multi-user.target"];
            after = ["network.target" "surrealdb-saas.service"];
            requires = ["surrealdb-saas.service"];

            serviceConfig = {
              Type = "simple";
              User = "minne-saas";
              Group = "minne-saas";
              WorkingDirectory = cfg.dataDir;
              ExecStart = pkgs.writeShellScript "start-minne-saas-worker" ''
                # Bridge SURREALDB_USER (from credentials) to SURREALDB_USERNAME (expected by app)
                if [ -z "$SURREALDB_USERNAME" ] && [ -n "$SURREALDB_USER" ]; then
                  export SURREALDB_USERNAME="$SURREALDB_USER"
                fi
                # Bridge SURREALDB_PASS (if used) to SURREALDB_PASSWORD
                if [ -z "$SURREALDB_PASSWORD" ] && [ -n "$SURREALDB_PASS" ]; then
                  export SURREALDB_PASSWORD="$SURREALDB_PASS"
                fi

                exec ${inputs.saas-minne.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/saas-worker
              '';
              Restart = "always";
              RestartSec = "10";

              # Basic environment variables
              Environment = [
                "SURREALDB_ADDRESS=ws://${cfg.surrealdb.host}:${toString cfg.surrealdb.port}"
                "HTTP_PORT=${toString cfg.port}"
                "RUST_LOG=${cfg.logLevel}"
                "DATA_DIR=${cfg.dataDir}"
                "DEMO_MODE=${lib.boolToString cfg.demoMode}"
                "DEMO_ALLOWED_MUTATING_PATHS=${lib.concatStringsSep "," cfg.demoAllowedMutatingPaths}"
              ];

              # Load environment file for all secrets
              EnvironmentFile = [
                (config.my.secrets.getPath "minne-saas" "env")
              ];
            };
          };
        };

        # Ensure data directories exist
        tmpfiles.rules = [
          "d ${cfg.dataDir} 0755 minne-saas minne-saas -"
          "d ${cfg.surrealdb.dataDir} 0755 surrealdb surrealdb -"
        ];
      };

      # Create minne-saas user and group
      users.users.minne-saas = {
        isSystemUser = true;
        group = "minne-saas";
        home = cfg.dataDir;
        createHome = true;
      };

      users.groups.minne-saas = {};

      my.exposure.services.minne-saas = lib.mkIf cfg.exposure.enable {
        upstream = {
          host = cfg.address;
          inherit (cfg) port;
        };
        router = {
          inherit (cfg.exposure.router) enable targets;
        };
        http.virtualHosts =
          lib.optional (cfg.exposure.domain != null) {
            inherit (cfg.exposure) domain;
            inherit (cfg.exposure) public cloudflareProxied;
            websockets = false;
            extraConfig = ''
              proxy_set_header Connection "close";
              proxy_http_version 1.1;
              chunked_transfer_encoding off;
              proxy_buffering off;
              proxy_cache off;
            '';
          }
          ++ lib.optional (cfg.exposure.demoDomain != null) {
            domain = cfg.exposure.demoDomain;
            inherit (cfg.exposure) public cloudflareProxied;
            websockets = false;
            publishDns = false;
            extraConfig = ''
              return 301 https://${cfg.exposure.domain}$request_uri;
            '';
          };
        firewall.local = {
          enable = cfg.firewallTcpPorts != [] || cfg.firewallUdpPorts != [];
          tcp = cfg.firewallTcpPorts;
          udp = cfg.firewallUdpPorts;
        };
      };
    };
  };
}
