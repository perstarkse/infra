_: {
  config.flake.nixosModules.oh-my-opencode = {
    config,
    lib,
    pkgs,
    ...
  }: let
    omoLib = import ./_install.nix {inherit lib;};

    cfg = config.my.oh-my-opencode;
    omoPkg = cfg.package;
    opencodePkg = cfg.opencodePackage;
    ocConfigDir = "${cfg.configDir}/opencode";
    opencodeBin = lib.getExe opencodePkg;
    omoBin = lib.getExe omoPkg;
    installStamp = "${cfg.configDir}/.install-stamp";

    installArgs = omoLib.mkInstallArgs cfg.install;
    installFingerprint = omoLib.mkInstallFingerprint {
      inherit installArgs omoPkg;
    };

    initScript = pkgs.writeShellScript "oh-my-opencode-init" ''
      set -eu
      ${pkgs.coreutils}/bin/install -d -m 0750 -o ${cfg.user} -g ${cfg.group} "${ocConfigDir}"
      ${pkgs.coreutils}/bin/install -d -m 0750 -o ${cfg.user} -g ${cfg.group} "${ocConfigDir}/skills"
      ${pkgs.coreutils}/bin/install -d -m 0750 -o ${cfg.user} -g ${cfg.group} "${ocConfigDir}/agents"
      ${pkgs.coreutils}/bin/install -d -m 0750 -o ${cfg.user} -g ${cfg.group} "${ocConfigDir}/commands"

      ${lib.concatMapStringsSep "\n" (skill: ''
          target="${ocConfigDir}/skills/${skill.name}"
          if [ -L "$target" ]; then
            ${pkgs.coreutils}/bin/rm -f "$target"
          fi
          if [ ! -e "$target" ]; then
            ${pkgs.coreutils}/bin/ln -sfn ${skill.path} "$target"
            ${pkgs.coreutils}/bin/chown -h ${cfg.user}:${cfg.group} "$target"
          fi
        '')
        cfg.skillSources}

      ${lib.optionalString (cfg.agentSourceDir != null) ''
        for agentFile in ${cfg.agentSourceDir}/*.md; do
          name=$(basename "$agentFile")
          if [ ! -e "${ocConfigDir}/agents/$name" ]; then
            ${pkgs.coreutils}/bin/install -m 0640 -o ${cfg.user} -g ${cfg.group} "$agentFile" "${ocConfigDir}/agents/$name"
          fi
        done
      ''}

      ${lib.optionalString (cfg.defaultConfigFile != null) ''
        if [ ! -e "${ocConfigDir}/opencode.jsonc" ]; then
          ${pkgs.coreutils}/bin/install -m 0640 -o ${cfg.user} -g ${cfg.group} ${cfg.defaultConfigFile} "${ocConfigDir}/opencode.jsonc"
        fi
      ''}
    '';

    installScript = pkgs.writeShellScript "oh-my-opencode-install" ''
      set -eu
      export HOME=${cfg.home}
      export XDG_CONFIG_HOME=${cfg.configDir}
      ${omoLib.mkInstallIfChanged {
        inherit pkgs;
        stampPath = installStamp;
        fingerprint = installFingerprint;
        body = "${omoBin} install ${installArgs}";
      }}
    '';
  in {
    options.my.oh-my-opencode = {
      enable = lib.mkEnableOption "oh-my-opencode OpenCode daemon profile";

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.llm-agents.oh-my-opencode;
        defaultText = lib.literalExpression "pkgs.llm-agents.oh-my-opencode";
        description = "oh-my-opencode harness package.";
      };

      opencodePackage = lib.mkOption {
        type = lib.types.package;
        default = pkgs.llm-agents.opencode;
        defaultText = lib.literalExpression "pkgs.llm-agents.opencode";
        description = "OpenCode package paired with the harness.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 4097;
        description = "Loopback port for the oh-my-opencode daemon.";
      };

      listenAddress = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Listen address for the oh-my-opencode daemon.";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "oh-my-opencode";
        description = "Dedicated system user for the oh-my-opencode profile.";
      };

      group = lib.mkOption {
        type = lib.types.str;
        default = "oh-my-opencode";
        description = "System group for the oh-my-opencode profile.";
      };

      home = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/oh-my-opencode";
        description = "Home directory for auth tokens and runtime state.";
      };

      configDir = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.home}/.config/oh-my-opencode";
        defaultText = lib.literalExpression ''"''${config.my.oh-my-opencode.home}/.config/oh-my-opencode"'';
        description = "XDG_CONFIG_HOME for this profile. OpenCode reads <dir>/opencode/.";
      };

      reposPath = lib.mkOption {
        type = lib.types.str;
        default = "/home/${config.my.mainUser.name}/repos";
        defaultText = lib.literalExpression ''"/home/''${config.my.mainUser.name}/repos"'';
        description = "Workspace root the profile should be able to read and write.";
      };

      skillSources = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Name of the skill (appears in the skills directory).";
            };
            path = lib.mkOption {
              type = lib.types.path;
              description = "Path to the skill source directory.";
            };
          };
        });
        default = [];
        description = "Named skill sources to symlink into the profile skills directory.";
      };

      agentSourceDir = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Directory containing agent .md files to seed on first run.";
      };

      defaultConfigFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to seed as opencode.jsonc on first run.";
      };

      environment = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {};
        description = "Extra environment variables for the daemon process.";
      };

      environmentFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to a systemd EnvironmentFile for the daemon.";
      };

      install = {
        claude = lib.mkOption {
          type = lib.types.enum ["no" "yes" "max20"];
          default = "no";
          description = "Claude subscription flag passed to oh-my-opencode install.";
        };

        openai = lib.mkOption {
          type = lib.types.enum ["no" "yes"];
          default = "no";
        };

        gemini = lib.mkOption {
          type = lib.types.enum ["no" "yes"];
          default = "no";
        };

        copilot = lib.mkOption {
          type = lib.types.enum ["no" "yes"];
          default = "no";
        };

        opencodeZen = lib.mkOption {
          type = lib.types.enum ["no" "yes"];
          default = "no";
        };

        zaiCodingPlan = lib.mkOption {
          type = lib.types.enum ["no" "yes"];
          default = "no";
        };

        kimiForCoding = lib.mkOption {
          type = lib.types.enum ["no" "yes"];
          default = "no";
        };

        opencodeGo = lib.mkOption {
          type = lib.types.enum ["no" "yes"];
          default = "no";
        };

        vercelAiGateway = lib.mkOption {
          type = lib.types.enum ["no" "yes"];
          default = "no";
        };

        skipAuth = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Skip interactive auth hints during non-interactive install.";
        };
      };
    };

    config = lib.mkIf cfg.enable (let
      daemonPath = with pkgs; [
        git
        openssh
        opencodePkg
        omoPkg
        nodejs
        bun
        coreutils
        bashInteractive
      ];
      daemonEnvironment =
        {
          HOME = toString cfg.home;
          XDG_CONFIG_HOME = toString cfg.configDir;
        }
        // cfg.environment;
    in {
      users.groups.${cfg.group} = {};

      users.users.${cfg.user} = {
        isSystemUser = true;
        inherit (cfg) group home;
        createHome = true;
        extraGroups = ["users"];
      };

      systemd.tmpfiles.rules = [
        "d ${cfg.home} 0750 ${cfg.user} ${cfg.group} -"
        "d ${cfg.configDir} 0750 ${cfg.user} ${cfg.group} -"
        "Z ${cfg.reposPath} - - - - u:${cfg.user}:rwx"
      ];

      systemd.services.oh-my-opencode = {
        description = "oh-my-opencode OpenCode daemon";
        wantedBy = ["multi-user.target"];
        after = ["network-online.target"];
        wants = ["network-online.target"];

        path = daemonPath;

        serviceConfig =
          {
            Type = "simple";
            User = cfg.user;
            Group = cfg.group;
            WorkingDirectory = cfg.reposPath;
            ExecStartPre = [
              initScript
              installScript
            ];
            ExecStart = lib.concatStringsSep " " [
              opencodeBin
              "serve"
              "--hostname"
              cfg.listenAddress
              "--port"
              (toString cfg.port)
            ];
            Restart = "always";
            RestartSec = "5s";
            NoNewPrivileges = true;
            PrivateTmp = true;
            Environment = lib.concatStringsSep " " (
              lib.mapAttrsToList (k: v: "${k}=${v}") daemonEnvironment
            );
          }
          // lib.optionalAttrs (cfg.environmentFile != null) {
            EnvironmentFile = cfg.environmentFile;
          };
      };
    });
  };
}
