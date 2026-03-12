_: {
  config.flake.nixosModules.openchamber = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.openchamber;
    defaultPackage = pkgs.callPackage ../../pkgs/openchamber {};
    serviceUser =
      if cfg.runAsMainUser
      then config.my.mainUser.name
      else cfg.user;
    serviceGroup =
      if cfg.runAsMainUser
      then lib.attrByPath ["users" "users" config.my.mainUser.name "group"] "users" config
      else cfg.group;
    settingsFile =
      if cfg.projectPath == null
      then null
      else
        pkgs.writeText "openchamber-settings.json" (builtins.toJSON {
          projects = [
            ({
                id = cfg.projectId;
                path = cfg.projectPath;
                addedAt = 0;
                lastOpenedAt = 0;
              }
              // lib.optionalAttrs (cfg.projectLabel != null) {
                label = cfg.projectLabel;
              })
          ];
          activeProjectId = cfg.projectId;
          lastDirectory = cfg.projectPath;
        });
    initScript = pkgs.writeShellScript "openchamber-init" ''
      set -eu
      ${pkgs.coreutils}/bin/install -d -m 0750 -o ${serviceUser} -g ${serviceGroup} ${cfg.dataDir}
      ${lib.optionalString (settingsFile != null) ''
        if [ ! -e ${cfg.dataDir}/settings.json ]; then
          ${pkgs.coreutils}/bin/install -m 0640 -o ${serviceUser} -g ${serviceGroup} ${settingsFile} ${cfg.dataDir}/settings.json
        fi
      ''}
    '';
    firewallSourceRules = lib.concatMapStringsSep "\n" (source:
      if builtins.match ".*:.*" source != null
      then "ip6 saddr ${source} tcp dport ${toString cfg.port} accept"
      else "ip saddr ${source} tcp dport ${toString cfg.port} accept")
    cfg.allowedFirewallSources;
  in {
    options.my.openchamber = {
      enable = lib.mkEnableOption "OpenChamber web interface";

      package = lib.mkOption {
        type = lib.types.package;
        default = defaultPackage;
        defaultText = lib.literalExpression "pkgs.callPackage ../../pkgs/openchamber {}";
        description = "Package containing the openchamber binary.";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "openchamber";
        description = "System user to run OpenChamber when runAsMainUser is false.";
      };

      group = lib.mkOption {
        type = lib.types.str;
        default = "openchamber";
        description = "System group to run OpenChamber when runAsMainUser is false.";
      };

      runAsMainUser = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Run OpenChamber as my.mainUser.name instead of a dedicated system user.";
      };

      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/openchamber";
        description = "Persistent data directory for OpenChamber state.";
      };

      projectPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "/home/${config.my.mainUser.name}/repos";
        description = "Initial project path seeded into OpenChamber settings.";
      };

      projectId = lib.mkOption {
        type = lib.types.str;
        default = "default-project";
        description = "Stable ID for the seeded OpenChamber project entry.";
      };

      projectLabel = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = config.networking.hostName;
        description = "Optional label for the seeded OpenChamber project entry.";
      };

      listenAddress = lib.mkOption {
        type = lib.types.str;
        default = config.my.listenNetworkAddress;
        description = "Address for OpenChamber to bind on.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 3000;
        description = "HTTP port for OpenChamber.";
      };

      opencodeHost = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional external OpenCode base URL to connect to instead of starting a local one.";
      };

      opencodePort = lib.mkOption {
        type = lib.types.nullOr lib.types.port;
        default = null;
        description = "Optional external OpenCode port when using OPENCODE_SKIP_START without opencodeHost.";
      };

      opencodeSkipStart = lib.mkOption {
        type = lib.types.bool;
        default = cfg.opencodeHost != null || cfg.opencodePort != null;
        description = "Skip starting the bundled OpenCode server and connect to an external one instead.";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Open OpenChamber port in firewall.";
      };

      allowedFirewallSources = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["10.0.0.1"];
        description = "Source IPs/CIDRs allowed to access OpenChamber. When non-empty, only these sources are accepted.";
      };

      extraEnvironment = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {};
        description = "Additional environment variables for the OpenChamber service.";
      };
    };

    config = lib.mkIf cfg.enable {
      users.users = lib.mkIf (!cfg.runAsMainUser) {
        ${cfg.user} = {
          isSystemUser = true;
          inherit (cfg) group;
          home = cfg.dataDir;
          createHome = true;
        };
      };

      users.groups = lib.mkIf (!cfg.runAsMainUser) {
        ${cfg.group} = {};
      };

      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir} 0750 ${serviceUser} ${serviceGroup} -"
      ];

      systemd.services.openchamber = {
        description = "OpenChamber Web UI";
        wantedBy = ["multi-user.target"];
        after = ["network-online.target"];
        wants = ["network-online.target"];

        environment =
          {
            OPENCHAMBER_DATA_DIR = toString cfg.dataDir;
            OPENCHAMBER_HOST = cfg.listenAddress;
          }
          // lib.optionalAttrs cfg.opencodeSkipStart {
            OPENCHAMBER_SKIP_OPENCODE_START = "true";
          }
          // lib.optionalAttrs (cfg.opencodeHost != null) {
            OPENCODE_HOST = cfg.opencodeHost;
          }
          // lib.optionalAttrs (cfg.opencodePort != null) {
            OPENCODE_PORT = toString cfg.opencodePort;
          }
          // cfg.extraEnvironment;

        path = with pkgs; [
          git
          openssh
          opencode
          bun
          cloudflared
          nodejs
        ];

        serviceConfig = {
          Type = "simple";
          User = serviceUser;
          Group = serviceGroup;
          WorkingDirectory =
            if cfg.projectPath != null
            then cfg.projectPath
            else cfg.dataDir;
          ExecStartPre = [initScript];
          ExecStart = lib.concatStringsSep " " [
            (lib.getExe cfg.package)
            "serve"
            "--port"
            (toString cfg.port)
          ];
          Restart = "always";
          RestartSec = "5s";

          NoNewPrivileges = true;
          PrivateTmp = true;
        };
      };

      networking.firewall = {
        allowedTCPPorts = lib.mkIf (cfg.openFirewall && cfg.allowedFirewallSources == []) [cfg.port];
        extraInputRules = lib.mkIf (cfg.allowedFirewallSources != []) (lib.mkAfter ''
          ${firewallSourceRules}
          tcp dport ${toString cfg.port} drop
        '');
      };
    };
  };
}
