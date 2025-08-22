{inputs, ...}: {
  config.flake.nixosModules.minne = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.minne;
  in {
    options.my.minne = {
      enable = lib.mkEnableOption "Enable Minne service";

      port = lib.mkOption {
        type = lib.types.port;
        default = 3000;
        description = "Port for Minne to listen on";
      };

      address = lib.mkOption {
        type = lib.types.str;
        default = "0.0.0.0";
        description = "Address for Minne to bind to";
      };

      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/minne";
        description = "Directory to store Minne data";
      };

      surrealdb = {
        host = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "SurrealDB host address";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 8220;
          description = "SurrealDB port";
        };
      };

      logLevel = lib.mkOption {
        type = lib.types.str;
        default = "info";
        description = "Log level for Minne";
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
          tcp = [3000];
          udp = [];
        };
        description = "Firewall port configuration for Minne";
      };
    };

    config = lib.mkIf cfg.enable {
      # Minne service configuration
      systemd.services.minne = {
        description = "Minne - Personal Knowledge Management";
        wantedBy = ["multi-user.target"];
        after = ["network.target" "surrealdb.service"];
        requires = ["surrealdb.service"];

        serviceConfig = {
          Type = "simple";
          User = "minne";
          Group = "minne";
          WorkingDirectory = cfg.dataDir;
          ExecStart = "${inputs.minne.packages.${pkgs.system}.default}/bin/main";
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
          EnvironmentFile =  [
            (config.my.secrets.getPath "minne-env" "env")
          ];
        };
      };

      # Create minne user and group
      users.users.minne = {
        isSystemUser = true;
        group = "minne";
        home = cfg.dataDir;
        createHome = true;
      };

      users.groups.minne = {};

      # Firewall configuration
      networking.firewall.allowedTCPPorts = cfg.firewallPorts.tcp;
      networking.firewall.allowedUDPPorts = cfg.firewallPorts.udp;

      # Ensure data directory exists
      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir} 0755 minne minne -"
      ];
    };
  };
}
