_: {
  config.flake.nixosModules.opencode = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.opencode;
    ocConfigDir = "${cfg.configDir}/opencode";
    opencodeBin =
      if cfg.npmPackageBin != null
      then "${cfg.home}/.local/bin/opencode"
      else lib.getExe pkgs.opencode;
    initScript = pkgs.writeShellScript "opencode-shared-init" ''
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
    copyOpencodeBin = pkgs.writeShellScript "copy-opencode-bin" ''
      set -eu
      src="${cfg.npmPackageBin}"
      if [ -f "$src" ]; then
        dst="${cfg.home}/.local/bin/opencode"
        ${pkgs.coreutils}/bin/mkdir -p "$(dirname "$dst")"
        ${pkgs.coreutils}/bin/install -m 0755 -o ${cfg.user} -g ${cfg.group} "$src" "$dst"
      fi
    '';
    daemonPath = with pkgs; [
      git
      openssh
      opencode
      nodejs
      coreutils
      bashInteractive
    ];
    opencodeSharedBin = pkgs.writeShellScriptBin "opencode-shared" ''
      export HOME=${cfg.home}
      export XDG_CONFIG_HOME=${cfg.configDir}
      exec ${opencodeBin} "$@"
    '';
  in {
    options.my.opencode = {
      enable = lib.mkEnableOption "Shared OpenCode daemon";

      port = lib.mkOption {
        type = lib.types.port;
        default = 4096;
        description = "Loopback port for the OpenCode daemon.";
      };

      listenAddress = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Listen address for the OpenCode daemon.";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = config.my.mainUser.name;
        defaultText = lib.literalExpression ''config.my.mainUser.name'';
        description = "System user for the OpenCode daemon.";
      };

      group = lib.mkOption {
        type = lib.types.str;
        default = lib.attrByPath ["users" "users" config.my.mainUser.name "group"] "users" config;
        defaultText = lib.literalExpression ''lib.attrByPath ["users" "users" config.my.mainUser.name "group"] "users" config'';
        description = "System group for the OpenCode daemon.";
      };

      home = lib.mkOption {
        type = lib.types.path;
        default = "/home/${cfg.user}";
        defaultText = lib.literalExpression ''"/home/''${config.my.opencode.user}"'';
        description = "Home directory for the OpenCode daemon user. Auth tokens and data are placed here.";
      };

      configDir = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.home}/.config/opencode-shared";
        defaultText = lib.literalExpression ''"''${config.my.opencode.home}/.config/opencode-shared"'';
        description = "Sets XDG_CONFIG_HOME for the OpenCode daemon. OpenCode reads config from <dir>/opencode/. Separate from the user's personal ~/.config/opencode to avoid collision.";
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
              description = "Path to the skill source directory containing SKILL.md and optionally rules/ or other files.";
            };
          };
        });
        default = [];
        example = lib.literalExpression ''
          [
            { name = "rust-skills"; path = inputs.rust-skills; }
            { name = "nixos-deployment"; path = ./assets/opencode/skills/nixos-deployment; }
          ]
        '';
        description = "Named skill sources to symlink into the daemon's skills directory.";
      };

      agentSourceDir = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Directory containing agent .md files to seed into the daemon's agents directory on first run.";
      };

      defaultConfigFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to seed as opencode.jsonc on first run. Never overwrites existing file.";
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

      npmPackageBin = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/home/p/.npm-global/bin/opencode";
        description = "Path to an npm-global opencode binary to use instead of the nixpkgs one.";
      };
    };

    config = lib.mkIf cfg.enable {
      users.users.${cfg.user} = lib.mkIf (cfg.user != config.my.mainUser.name) {
        isSystemUser = true;
        inherit (cfg) group home;
        createHome = true;
        extraGroups = ["users"];
      };

      users.groups.${cfg.group} = lib.mkIf (cfg.group != config.my.mainUser.group) {};

      environment.systemPackages = [opencodeSharedBin];

      systemd.services.opencode-shared = {
        description = "Shared OpenCode daemon";
        wantedBy = ["multi-user.target"];
        after = ["network-online.target"];
        wants = ["network-online.target"];

        path = daemonPath;

        serviceConfig =
          {
            Type = "simple";
            User = cfg.user;
            Group = cfg.group;
            WorkingDirectory = cfg.home;
            ExecStartPre =
              [initScript]
              ++ lib.optionals (cfg.npmPackageBin != null) ["+${copyOpencodeBin}"];
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
          }
          // lib.optionalAttrs (cfg.environment != {}) {
            Environment = lib.concatStringsSep " " (
              lib.mapAttrsToList (k: v: "${k}=${v}") cfg.environment
            );
          }
          // lib.optionalAttrs (cfg.environmentFile != null) {
            EnvironmentFile = cfg.environmentFile;
          };
      };
    };
  };
}