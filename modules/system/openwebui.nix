{
  config.flake.nixosModules.openwebui = {
    config,
    lib,
    pkgs,
    mkStandardExposureOptions,
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

      exposure = mkStandardExposureOptions {
        subject = "OpenWebUI";
        visibility = "public";
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
            ExecStart = "${pkgs.podman}/bin/podman pull ghcr.io/open-webui/open-webui:main";
            ExecStartPost = "${pkgs.podman}/bin/podman container restart openwebui";
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

      my.exposure.services.openwebui = lib.mkIf cfg.exposure.enable {
        upstream = {
          host = config.my.listenNetworkAddress;
          inherit (cfg) port;
        };
        router = {inherit (cfg.exposure.router) enable targets;};
        http.virtualHosts = lib.optional (cfg.exposure.domain != null) {
          inherit (cfg.exposure) domain;
          inherit (cfg.exposure) public cloudflareProxied;
        };
        firewall.local = {
          enable = cfg.firewallTcpPorts != [] || cfg.firewallUdpPorts != [];
          tcp = cfg.firewallTcpPorts;
          udp = cfg.firewallUdpPorts;
        };
      };

      # OpenWebUI container configuration
      virtualisation.oci-containers.containers.openwebui = {
        image = "ghcr.io/open-webui/open-webui:main";
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
