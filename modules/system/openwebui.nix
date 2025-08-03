{
  config.flake.nixosModules.openwebui = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.openwebui;
  in {
    options.my.openwebui = {
      port = lib.mkOption {
        type = lib.types.port;
        default = 7909;
        description = "Port for OpenWebUI to listen on";
      };

      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "/data/.state/openwebui";
        description = "Directory to store OpenWebUI data";
      };

      timezone = lib.mkOption {
        type = lib.types.str;
        default = "Europe/Amsterdam";
        description = "Timezone for the OpenWebUI container";
      };

      autoUpdate = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable automatic container updates";
      };

      updateSchedule = lib.mkOption {
        type = lib.types.str;
        default = "weekly";
        description = "Schedule for container updates (daily, weekly, monthly)";
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
          tcp = [7909];
          udp = [];
        };
        description = "Firewall port configuration for OpenWebUI";
      };
    };

    config = {
      # Enable OCI containers (Podman)
      virtualisation.oci-containers.backend = "podman";

      # Ensure data directory exists
      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir} 0755 root root - -"
      ];

      # Firewall configuration
      networking.firewall.allowedTCPPorts = cfg.firewallPorts.tcp;
      networking.firewall.allowedUDPPorts = cfg.firewallPorts.udp;

      # OpenWebUI container configuration
      virtualisation.oci-containers.containers.openwebui = {
        image = "ghcr.io/open-webui/open-webui:main";
        environment = {
          TZ = cfg.timezone;
        };
        ports = ["${toString cfg.port}:8080"];
        volumes = ["${cfg.dataDir}:/app/backend/data"];
        autoStart = true;
        autoUpdate = cfg.autoUpdate;
      };

      # Auto-update service for container
      systemd.services.openwebui-update = lib.mkIf cfg.autoUpdate {
        description = "Update OpenWebUI container";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.podman}/bin/podman pull ghcr.io/open-webui/open-webui:main";
          ExecStartPost = "${pkgs.podman}/bin/podman container restart openwebui";
        };
      };

      # Timer for automatic updates
      systemd.timers.openwebui-update = lib.mkIf cfg.autoUpdate {
        description = "Timer for OpenWebUI container updates";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = if cfg.updateSchedule == "daily" then "daily"
                      else if cfg.updateSchedule == "weekly" then "weekly"
                      else if cfg.updateSchedule == "monthly" then "monthly"
                      else "weekly";
          Persistent = true;
        };
      };
    };
  };
} 