_: {
  config.flake.nixosModules.openchamber = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.openchamber;
    defaultPackage = pkgs.callPackage ../../../pkgs/openchamber {};
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
    opencodeInitScript = let
      opcodeUser = cfg.sharedOpencode.user;
      opcodeHome = cfg.sharedOpencode.home;
      configDir = "${opcodeHome}/.config/opencode";
    in
      pkgs.writeShellScript "opencode-shared-init" ''
        set -eu
        ${pkgs.coreutils}/bin/install -d -m 0750 -o ${opcodeUser} -g ${serviceGroup} "${configDir}"
        ${pkgs.coreutils}/bin/install -d -m 0750 -o ${opcodeUser} -g ${serviceGroup} "${configDir}/skills"
        ${pkgs.coreutils}/bin/install -d -m 0750 -o ${opcodeUser} -g ${serviceGroup} "${configDir}/agents"
        ${pkgs.coreutils}/bin/install -d -m 0750 -o ${opcodeUser} -g ${serviceGroup} "${configDir}/commands"

        # Symlink skill sources (idempotent: remove stale, re-link)
        # If a source has subdirs but none has SKILL.md, link the whole source.
        ${lib.concatMapStringsSep "\n" (src: ''
            shopt -s nullglob
            subdirs=(${src}/*/)
            if [ ''${#subdirs[@]} -gt 0 ]; then
              hasSkill=false
              for sd in "''${subdirs[@]}"; do
                if [ -f "$sd/SKILL.md" ]; then hasSkill=true; break; fi
              done
              if [ "$hasSkill" = true ]; then
                for skillDir in "''${subdirs[@]}"; do
                  skillName=$(basename "$skillDir")
                  target="${configDir}/skills/$skillName"
                  if [ -L "$target" ]; then
                    ${pkgs.coreutils}/bin/rm -f "$target"
                  fi
                  if [ ! -e "$target" ]; then
                    ${pkgs.coreutils}/bin/ln -sfn "$skillDir" "$target"
                    ${pkgs.coreutils}/bin/chown -h ${opcodeUser}:${serviceGroup} "$target"
                  fi
                done
              else
                skillName=$(basename ${src})
                target="${configDir}/skills/$skillName"
                if [ -L "$target" ]; then
                  ${pkgs.coreutils}/bin/rm -f "$target"
                fi
                if [ ! -e "$target" ]; then
                  ${pkgs.coreutils}/bin/ln -sfn ${src} "$target"
                  ${pkgs.coreutils}/bin/chown -h ${opcodeUser}:${serviceGroup} "$target"
                fi
              fi
            else
              skillName=$(basename ${src})
              target="${configDir}/skills/$skillName"
              if [ -L "$target" ]; then
                ${pkgs.coreutils}/bin/rm -f "$target"
              fi
              if [ ! -e "$target" ]; then
                ${pkgs.coreutils}/bin/ln -sfn ${src} "$target"
                ${pkgs.coreutils}/bin/chown -h ${opcodeUser}:${serviceGroup} "$target"
              fi
            fi
          '')
          cfg.sharedOpencode.skillSources}

        # Seed agent defaults (seed-once: never overwrite)
        ${lib.optionalString (cfg.sharedOpencode.agentSourceDir != null) ''
          for agentFile in ${cfg.sharedOpencode.agentSourceDir}/*.md; do
            name=$(basename "$agentFile")
            if [ ! -e "${configDir}/agents/$name" ]; then
              ${pkgs.coreutils}/bin/install -m 0640 -o ${opcodeUser} -g ${serviceGroup} "$agentFile" "${configDir}/agents/$name"
            fi
          done
        ''}

        # Seed default config (seed-once: never overwrite)
        ${lib.optionalString (cfg.sharedOpencode.defaultConfigFile != null) ''
          if [ ! -e "${configDir}/opencode.json" ]; then
            ${pkgs.coreutils}/bin/install -m 0640 -o ${opcodeUser} -g ${serviceGroup} ${cfg.sharedOpencode.defaultConfigFile} "${configDir}/opencode.json"
          fi
        ''}
      '';
    opencodeBinary =
      if cfg.sharedOpencode.npmPackageBin != null
      then "${cfg.sharedOpencode.home}/.local/bin/opencode"
      else lib.getExe pkgs.opencode;
    copyOpencodeBin = pkgs.writeShellScript "copy-opencode-bin" ''
      set -eu
      src="${cfg.sharedOpencode.npmPackageBin}"
      if [ -f "$src" ]; then
        dst="${cfg.sharedOpencode.home}/.local/bin/opencode"
        ${pkgs.coreutils}/bin/mkdir -p "$(dirname "$dst")"
        ${pkgs.coreutils}/bin/install -m 0755 -o ${cfg.sharedOpencode.user} -g ${serviceGroup} "$src" "$dst"
      fi
    '';
    commonPath = with pkgs;
      [
        git
        openssh
        opencode
        bun
        cloudflared
        nodejs
        nodePackages.pnpm
        bashInteractive
        coreutils
        gnugrep
        gawk
        findutils
        nix
        devenv
      ]
      ++ lib.optionals (cfg.sharedOpencode.npmPackageBin != null) [
        "${cfg.sharedOpencode.home}/.local/bin"
      ];
    firewallSourceRules = lib.concatMapStringsSep "\n" (source:
      if builtins.match ".*:.*" source != null
      then "ip6 saddr ${source} tcp dport ${toString cfg.port} accept"
      else "ip saddr ${source} tcp dport ${toString cfg.port} accept")
    cfg.allowedFirewallSources;
    mkFirewallExtraCommands = port: sources: let
      allowRules =
        map (
          source:
            if builtins.match ".*:.*" source != null
            then "${pkgs.iptables}/bin/ip6tables -A nixos-fw -p tcp -s ${source} --dport ${toString port} -j ACCEPT"
            else "${pkgs.iptables}/bin/iptables -A nixos-fw -p tcp -s ${source} --dport ${toString port} -j ACCEPT"
        )
        sources;
    in
      lib.concatStringsSep "\n" (
        allowRules
        ++ [
          "${pkgs.iptables}/bin/iptables -A nixos-fw -p tcp --dport ${toString port} -j DROP"
          "${pkgs.iptables}/bin/ip6tables -A nixos-fw -p tcp --dport ${toString port} -j DROP"
        ]
      );
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
        type = with lib.types; nullOr (addCheck str (_: !cfg.sharedOpencode.enable));
        default = null;
        description = "Optional external OpenCode base URL to connect to instead of starting a local one. Cannot be used when sharedOpencode.enable is true.";
      };

      opencodePort = lib.mkOption {
        type = with lib.types; nullOr (addCheck port (_: !cfg.sharedOpencode.enable));
        default = null;
        description = "Optional external OpenCode port when using OPENCODE_SKIP_START without opencodeHost. Cannot be used when sharedOpencode.enable is true.";
      };

      sharedOpencode = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = cfg.opencodeHost == null && cfg.opencodePort == null;
          description = "Run a shared local OpenCode daemon and point OpenChamber at it.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 4096;
          description = "Loopback port for the shared OpenCode daemon.";
        };

        listenAddress = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "Listen address for the shared OpenCode daemon.";
        };

        user = lib.mkOption {
          type = lib.types.str;
          default = serviceUser;
          description = "System user for the shared OpenCode daemon. Defaults to the main service user. Set to a different user to isolate the daemon's config and data.";
        };

        home = lib.mkOption {
          type = lib.types.path;
          default = "/home/${cfg.sharedOpencode.user}";
          defaultText = lib.literalExpression ''"/home/''${sharedOpencode.user}"'';
          description = "Home directory for the shared OpenCode daemon user. Config, skills, agents, and data are placed here.";
        };

        skillSources = lib.mkOption {
          type = lib.types.listOf lib.types.path;
          default = [];
          description = "List of source directories containing skill subdirectories (each with a SKILL.md). Symlinked into the daemon's skills directory at startup.";
        };

        agentSourceDir = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Directory containing agent .md files to seed into the daemon's agents directory on first run. Existing files are never overwritten.";
        };

        defaultConfigFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Path to an opencode JSON config file to seed as opencode.json in the daemon's config directory on first run. Never overwrites an existing file. The source filename is irrelevant; it is always deployed as opencode.json.";
        };

        environment = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {};
          description = "Extra environment variables for the shared OpenCode daemon process. Use this to inject secrets (e.g. CONTEXT7_API_KEY) without hardcoding them in the config file.";
        };

        environmentFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Path to a systemd EnvironmentFile for the shared OpenCode daemon. Prefer this over environment for secrets — use config.my.secrets.getPath to reference a clan vars generator.";
        };

        npmPackageBin = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "/home/p/.npm-global/bin/opencode";
          description = "Path to the npm-global opencode binary to use instead of the nixpkgs one. Copied at runtime before the daemon starts, so no rebuild is needed after npm updates.";
        };
      };

      opencodeSkipStart = lib.mkOption {
        type = lib.types.bool;
        default = cfg.sharedOpencode.enable || cfg.opencodeHost != null || cfg.opencodePort != null;
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
        example = ["10.0.0.10" "10.0.0.0/24"];
        description = "Source IPs/CIDRs allowed to access OpenChamber. Leave empty to allow all sources allowed by openFirewall; entries are matched literally, so use CIDRs like 10.0.0.0/24 rather than 0.0.0.0 when you mean a whole network.";
      };

      extraEnvironment = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {};
        description = "Additional environment variables for the OpenChamber service.";
      };
    };

    config = lib.mkIf cfg.enable {
      users.users = lib.mkMerge [
        (lib.mkIf (!cfg.runAsMainUser) {
          ${cfg.user} = {
            isSystemUser = true;
            inherit (cfg) group;
            home = cfg.dataDir;
            createHome = true;
          };
        })
        (lib.mkIf (cfg.sharedOpencode.user != serviceUser) {
          ${cfg.sharedOpencode.user} = {
            isSystemUser = true;
            group = serviceGroup;
            inherit (cfg.sharedOpencode) home;
            createHome = true;
            extraGroups = ["users"];
          };
        })
      ];

      users.groups = lib.mkIf (!cfg.runAsMainUser) {
        ${cfg.group} = {};
      };

      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir} 0750 ${serviceUser} ${serviceGroup} -"
      ];

      systemd.services.openchamber-opencode = lib.mkIf cfg.sharedOpencode.enable {
        description = "Shared OpenCode daemon for OpenChamber";
        wantedBy = ["multi-user.target"];
        after = ["network-online.target"];
        wants = ["network-online.target"];

        path = commonPath;

        serviceConfig =
          {
            Type = "simple";
            User = cfg.sharedOpencode.user;
            Group = serviceGroup;
            WorkingDirectory = cfg.sharedOpencode.home;
            ExecStartPre =
              [opencodeInitScript]
              ++ lib.optionals (cfg.sharedOpencode.npmPackageBin != null) ["+${copyOpencodeBin}"];
            ExecStart = lib.concatStringsSep " " [
              opencodeBinary
              "serve"
              "--hostname"
              cfg.sharedOpencode.listenAddress
              "--port"
              (toString cfg.sharedOpencode.port)
            ];
            Restart = "always";
            RestartSec = "5s";

            NoNewPrivileges = true;
            PrivateTmp = true;
          }
          // lib.optionalAttrs (cfg.sharedOpencode.user != serviceUser || cfg.sharedOpencode.environment != {}) {
            Environment = lib.concatStringsSep " " (
              lib.optional (cfg.sharedOpencode.user != serviceUser) "HOME=${cfg.sharedOpencode.home}"
              ++ lib.mapAttrsToList (k: v: "${k}=${v}") cfg.sharedOpencode.environment
            );
          }
          // lib.optionalAttrs (cfg.sharedOpencode.environmentFile != null) {
            EnvironmentFile = cfg.sharedOpencode.environmentFile;
          };
      };

      systemd.services.openchamber = {
        description = "OpenChamber Web UI";
        wantedBy = ["multi-user.target"];
        after = ["network-online.target"] ++ lib.optionals cfg.sharedOpencode.enable ["openchamber-opencode.service"];
        wants = ["network-online.target"] ++ lib.optionals cfg.sharedOpencode.enable ["openchamber-opencode.service"];

        environment =
          {
            OPENCHAMBER_DATA_DIR = toString cfg.dataDir;
            OPENCHAMBER_HOST = cfg.listenAddress;
          }
          // lib.optionalAttrs cfg.opencodeSkipStart {
            OPENCHAMBER_SKIP_OPENCODE_START = "true";
          }
          // lib.optionalAttrs (cfg.sharedOpencode.enable || cfg.opencodeHost != null) {
            OPENCODE_HOST =
              if cfg.sharedOpencode.enable
              then "http://${cfg.sharedOpencode.listenAddress}:${toString cfg.sharedOpencode.port}"
              else cfg.opencodeHost;
          }
          // lib.optionalAttrs (!cfg.sharedOpencode.enable && cfg.opencodePort != null) {
            OPENCODE_PORT = toString cfg.opencodePort;
          }
          // cfg.extraEnvironment;

        path = commonPath;

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
            "--foreground"
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
        extraCommands = lib.mkIf (!config.networking.nftables.enable && cfg.allowedFirewallSources != []) (lib.mkAfter ''
          ${mkFirewallExtraCommands cfg.port cfg.allowedFirewallSources}
        '');
      };
    };
  };
}
