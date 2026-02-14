_: {
  config.flake.nixosModules.wake-proxy = {
    config,
    lib,
    ...
  }: let
    cfg = config.my.wake-proxy;
    envFile = config.my.secrets.getPath cfg.secretName "env";
  in {
    options.my.wake-proxy = {
      enable = lib.mkEnableOption "Wake-on-LAN authenticated reverse proxy";

      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        description = "Package containing the wol-web-proxy binary.";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "wake-proxy";
        description = "System user to run wake-proxy.";
      };

      group = lib.mkOption {
        type = lib.types.str;
        default = "wake-proxy";
        description = "System group to run wake-proxy.";
      };

      listenAddress = lib.mkOption {
        type = lib.types.str;
        default = config.my.listenNetworkAddress;
        description = "Address to bind the wake-proxy service to.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 8091;
        description = "Port for wake-proxy.";
      };

      upstreamHost = lib.mkOption {
        type = lib.types.str;
        description = "Upstream host to proxy after wake.";
      };

      upstreamPort = lib.mkOption {
        type = lib.types.port;
        description = "Upstream port to proxy after wake.";
      };

      healthPath = lib.mkOption {
        type = lib.types.str;
        default = "/health";
        description = "HTTP health path on upstream.";
      };

      wolMac = lib.mkOption {
        type = lib.types.str;
        description = "Wake-on-LAN MAC address in aa:bb:cc:dd:ee:ff format.";
      };

      wolBroadcastIp = lib.mkOption {
        type = lib.types.str;
        default = "255.255.255.255";
        description = "Broadcast IP for WoL packets.";
      };

      wolBroadcastPort = lib.mkOption {
        type = lib.types.port;
        default = 9;
        description = "Broadcast port for WoL packets.";
      };

      wakeTimeout = lib.mkOption {
        type = lib.types.int;
        default = 180;
        description = "Maximum seconds to wait for wake readiness.";
      };

      pollInterval = lib.mkOption {
        type = lib.types.int;
        default = 2;
        description = "Seconds between readiness polls.";
      };

      readyCacheTtl = lib.mkOption {
        type = lib.types.int;
        default = 5;
        description = "Seconds to cache ready state to avoid redundant probes.";
      };

      edgeWaitTimeout = lib.mkOption {
        type = lib.types.int;
        default = 20;
        description = "Max seconds to wait per request before returning still-waking page.";
      };

      sessionTtl = lib.mkOption {
        type = lib.types.int;
        default = 43200;
        description = "Session cookie TTL in seconds.";
      };

      cookieSecure = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Set secure flag on auth cookie.";
      };

      loginMaxFailures = lib.mkOption {
        type = lib.types.int;
        default = 5;
        description = "Max login failures before lockout.";
      };

      loginLockoutSecs = lib.mkOption {
        type = lib.types.int;
        default = 60;
        description = "Lockout duration in seconds.";
      };

      loginWindowSecs = lib.mkOption {
        type = lib.types.int;
        default = 300;
        description = "Rolling window for counting failed attempts.";
      };

      loginMaxTrackedIps = lib.mkOption {
        type = lib.types.int;
        default = 10000;
        description = "Maximum IP attempt records to retain for brute-force tracking.";
      };

      trustProxyHeaders = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Trust forwarded headers when peer address is explicitly trusted.";
      };

      trustedProxyIps = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Peer IPs allowed to supply trusted X-Forwarded-* headers.";
      };

      secretName = lib.mkOption {
        type = lib.types.str;
        default = "wake-proxy";
        description = "Secret generator name that provides env file with auth secrets.";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Open wake-proxy port in firewall.";
      };
    };

    config = lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.package != null;
          message = "my.wake-proxy.package must be set when my.wake-proxy.enable = true";
        }
      ];

      my.secrets.allowReadAccess = [
        {
          readers = [cfg.user];
          path = envFile;
        }
      ];

      users.users.${cfg.user} = {
        isSystemUser = true;
        inherit (cfg) group;
      };

      users.groups.${cfg.group} = {};

      systemd.services.wake-proxy = {
        description = "Wake-on-LAN web proxy";
        wantedBy = ["multi-user.target"];
        after = ["network-online.target"];
        wants = ["network-online.target"];

        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          ExecStart = lib.getExe cfg.package;
          Restart = "always";
          RestartSec = "5s";

          Environment = [
            "WOL_PROXY_UPSTREAM_HOST=${cfg.upstreamHost}"
            "WOL_PROXY_UPSTREAM_PORT=${toString cfg.upstreamPort}"
            "WOL_PROXY_HEALTH_PATH=${cfg.healthPath}"
            "WOL_PROXY_WOL_MAC=${cfg.wolMac}"
            "WOL_PROXY_WOL_BROADCAST_IP=${cfg.wolBroadcastIp}"
            "WOL_PROXY_WOL_BROADCAST_PORT=${toString cfg.wolBroadcastPort}"
            "WOL_PROXY_WAKE_TIMEOUT=${toString cfg.wakeTimeout}"
            "WOL_PROXY_POLL_INTERVAL=${toString cfg.pollInterval}"
            "WOL_PROXY_READY_CACHE_TTL=${toString cfg.readyCacheTtl}"
            "WOL_PROXY_EDGE_WAIT_TIMEOUT=${toString cfg.edgeWaitTimeout}"
            "WOL_PROXY_BIND_ADDR=${cfg.listenAddress}:${toString cfg.port}"
            "WOL_PROXY_SESSION_TTL_SECS=${toString cfg.sessionTtl}"
            "WOL_PROXY_COOKIE_SECURE=${lib.boolToString cfg.cookieSecure}"
            "WOL_PROXY_LOGIN_MAX_FAILURES=${toString cfg.loginMaxFailures}"
            "WOL_PROXY_LOGIN_LOCKOUT_SECS=${toString cfg.loginLockoutSecs}"
            "WOL_PROXY_LOGIN_WINDOW_SECS=${toString cfg.loginWindowSecs}"
            "WOL_PROXY_LOGIN_MAX_TRACKED_IPS=${toString cfg.loginMaxTrackedIps}"
            "WOL_PROXY_TRUST_PROXY_HEADERS=${lib.boolToString cfg.trustProxyHeaders}"
            "WOL_PROXY_TRUSTED_PROXY_IPS=${lib.concatStringsSep "," cfg.trustedProxyIps}"
          ];
          EnvironmentFile = [envFile];

          NoNewPrivileges = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectControlGroups = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectClock = true;
          ProtectHostname = true;
          RestrictSUIDSGID = true;
          RestrictRealtime = true;
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          RemoveIPC = true;
          CapabilityBoundingSet = "";
          AmbientCapabilities = "";
          SystemCallArchitectures = "native";
        };
      };

      networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [cfg.port];
    };
  };
}
