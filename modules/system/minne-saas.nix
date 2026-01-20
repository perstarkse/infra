{inputs, ...}: {
  config.flake.nixosModules.minne-saas = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.minne-saas;
    saasConfigFormat = pkgs.formats.yaml {};
    saasConfigFile = saasConfigFormat.generate "saas-config.yaml" cfg.saasConfig;
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
        default = "0.0.0.0";
        description = "Address for Minne SaaS Server to bind to";
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
      };

      logLevel = lib.mkOption {
        type = lib.types.str;
        default = "info";
        description = "Log level for Minne SaaS";
      };

      saasConfig = lib.mkOption {
        type = lib.types.submodule {
          freeformType = saasConfigFormat.type;
        };
        default = {};
        description = "Content of saas-config.yaml";
      };

      firewallPorts = lib.mkOption {
        type = lib.types.submodule {
          options = {
            tcp = lib.mkOption {
              type = lib.types.listOf lib.types.port;
              default = [];
              description = "TCP ports to allow through firewall";
            };
            udp = lib.mkOption {
              type = lib.types.listOf lib.types.port;
              default = [];
              description = "UDP ports to allow through firewall";
            };
          };
        };
        default = {
          tcp = [3003];
          udp = [];
        };
        description = "Firewall port configuration for Minne SaaS";
      };
    };

    config = lib.mkIf cfg.enable {
      # Minne SaaS Server service
      systemd.services.minne-saas-server = {
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
            
            exec ${inputs.saas-minne.packages.${pkgs.system}.default}/bin/saas-server
          '';
          Restart = "always";
          RestartSec = "10";



          # Basic environment variables
          Environment = [
            "SURREALDB_ADDRESS=ws://${cfg.surrealdb.host}:${toString cfg.surrealdb.port}"
            "HTTP_PORT=${toString cfg.port}"
            "RUST_LOG=${cfg.logLevel}"
            "DATA_DIR=${cfg.dataDir}"
          ];

          # Load environment file for all secrets
          EnvironmentFile = [
            (config.my.secrets.getPath "minne-saas" "env")
          ];
        };
      };

      # Minne SaaS Worker service
      systemd.services.minne-saas-worker = {
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

            exec ${inputs.saas-minne.packages.${pkgs.system}.default}/bin/saas-worker
          '';
          Restart = "always";
          RestartSec = "10";

          # Basic environment variables
          Environment = [
            "SURREALDB_ADDRESS=ws://${cfg.surrealdb.host}:${toString cfg.surrealdb.port}"
            "HTTP_PORT=${toString cfg.port}"
            "RUST_LOG=${cfg.logLevel}"
            "DATA_DIR=${cfg.dataDir}"
          ];

          # Load environment file for all secrets
          EnvironmentFile = [
            (config.my.secrets.getPath "minne-saas" "env")
          ];
        };
      };

      # Create minne-saas user and group
      users.users.minne-saas = {
        isSystemUser = true;
        group = "minne-saas";
        home = cfg.dataDir;
        createHome = true;
      };

      users.groups.minne-saas = {};

      # Firewall configuration
      networking.firewall.allowedTCPPorts = cfg.firewallPorts.tcp;
      networking.firewall.allowedUDPPorts = cfg.firewallPorts.udp;

      # Ensure data directory and config exist
      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir} 0755 minne-saas minne-saas -"
        "L+ ${cfg.dataDir}/saas-config.yaml - - - - ${saasConfigFile}"
      ];
    };
  };
}
