{inputs, ...}: {
  config.flake.nixosModules.minne = {
    config,
    lib,
    pkgs,
    mkStandardExposureOptions,
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
        default = config.my.listenNetworkAddress;
        description = "Address for Minne to bind to (defaults to my.listenNetworkAddress)";
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

      firewallTcpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [3000];
        description = "Additional TCP ports to open for Minne.";
      };
      firewallUdpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [];
        description = "UDP ports to open for Minne.";
      };

      exposure = mkStandardExposureOptions {
        subject = "Minne";
        visibility = "internal";
        withRouter = true;
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
          ExecStart = "${inputs.minne.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/main";
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

      my.exposure.services.minne = lib.mkIf cfg.exposure.enable {
        upstream = {
          host = cfg.address;
          inherit (cfg) port;
        };
        router = {
          inherit (cfg.exposure.router) enable targets;
        };
        http.virtualHosts = lib.optional (cfg.exposure.domain != null) {
          inherit (cfg.exposure) domain;
          inherit (cfg.exposure) lanOnly useWildcard;
          websockets = false;
          extraConfig = ''
            proxy_set_header Connection "close";
            proxy_http_version 1.1;
            chunked_transfer_encoding off;
            proxy_buffering off;
            proxy_cache off;
          '';
        };
        firewall.local = {
          enable = cfg.firewallTcpPorts != [] || cfg.firewallUdpPorts != [];
          tcp = cfg.firewallTcpPorts;
          udp = cfg.firewallUdpPorts;
        };
      };

      # Ensure data directory exists
      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir} 0755 minne minne -"
      ];
    };
  };
}
