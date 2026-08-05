{
  config.flake.nixosModules.openwebui = {
    config,
    lib,
    pkgs,
    mkStandardEndpointsOptions,
    ...
  }: let
    cfg = config.my.openwebui;
  in {
    options.my.openwebui = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable OpenWebUI";
      };

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

      image = lib.mkOption {
        type = lib.types.str;
        default = "ghcr.io/open-web-ui/open-webui:main";
        description = "OCI image (pin to a digest for reproducible updates)";
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

      firewallTcpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [8080];
        description = "Additional TCP ports to open for OpenWebUI.";
      };
      firewallUdpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [];
        description = "UDP ports to open for OpenWebUI.";
      };

      endpoints = mkStandardEndpointsOptions {
        subject = "OpenWebUI";
        visibility = "internal";
        withRouter = true;
      };
    };

    config = lib.mkIf cfg.enable {
      # Enable OCI containers (Podman)
      virtualisation.oci-containers.backend = "podman";
      systemd = {
        # Ensure data directory exists
        tmpfiles.rules = [
          "d ${cfg.dataDir} 0755 root root - -"
        ];

        # Auto-update service for container
        services.openwebui-update = lib.mkIf cfg.autoUpdate {
          description = "Update OpenWebUI container";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.podman}/bin/podman pull ${cfg.image}";
            ExecStartPost = [
              "${pkgs.podman}/bin/podman rm -f openwebui"
              "${pkgs.systemd}/bin/systemctl restart podman-openwebui"
            ];
          };
        };

        # Timer for automatic updates
        timers.openwebui-update = lib.mkIf cfg.autoUpdate {
          description = "Timer for OpenWebUI container updates";
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar =
              if cfg.updateSchedule == "daily"
              then "daily"
              else if cfg.updateSchedule == "weekly"
              then "weekly"
              else if cfg.updateSchedule == "monthly"
              then "monthly"
              else "weekly";
            Persistent = true;
          };
        };
      };

      my.endpoints.services.openwebui = lib.mkIf cfg.endpoints.enable {
        upstream = {
          host = config.my.listenNetworkAddress;
          inherit (cfg) port;
        };
        router = {inherit (cfg.endpoints.router) enable targets;};
        http.virtualHosts = lib.optional (cfg.endpoints.domain != null) {
          inherit (cfg.endpoints) domain;
          inherit (cfg.endpoints) lanOnly useWildcard;
        };
        firewall.local = {
          enable = cfg.firewallTcpPorts != [] || cfg.firewallUdpPorts != [];
          tcp = cfg.firewallTcpPorts;
          udp = cfg.firewallUdpPorts;
        };
      };

      # OpenWebUI container configuration
      virtualisation.oci-containers.containers.openwebui = {
        inherit (cfg) image;
        environment = {
          TZ = cfg.timezone;
          HOST = "0.0.0.0";
          # PORT = toString cfg.port;
        };
        # ports = ["0.0.0.0:${toString cfg.port}:8080"];
        volumes = ["${cfg.dataDir}:/app/backend/data"];
        autoStart = true;
        extraOptions = [
          "--network=host"
        ];
        # autoUpdate = cfg.autoUpdate;
      };
    };
  };
}
