_: {
  config.flake.homeModules.oh-my-opencode = {
    pkgs,
    lib,
    config,
    ...
  }: let
    omoLib = import ../system/oh-my-opencode/_install.nix {inherit lib;};

    cfg = config.programs.oh-my-opencode;

    omoPkg = pkgs.llm-agents.oh-my-opencode;
    opencodePkg = pkgs.llm-agents.opencode;
    omoBin = lib.getExe omoPkg;
    opencodeBin = lib.getExe opencodePkg;
    pluginPath = "file://${omoPkg}/lib/oh-my-opencode";

    omoConfigDir = "${config.xdg.configHome}/oh-my-opencode";
    omoOcDir = "${omoConfigDir}/opencode";
    installStamp = "${omoConfigDir}/.install-stamp";

    installArgs = omoLib.mkInstallArgs cfg.install;
    installFingerprint = omoLib.mkInstallFingerprint {
      inherit installArgs;
      inherit omoPkg;
      extra = pluginPath;
    };

    ohMyOpencodeWrapper = pkgs.writeShellScriptBin "oh-my-opencode" ''
      export XDG_CONFIG_HOME=${omoConfigDir}
      exec ${omoBin} "$@"
    '';

    opencodeOmoWrapper = pkgs.writeShellScriptBin "opencode-omo" ''
      export XDG_CONFIG_HOME=${omoConfigDir}
      exec ${opencodeBin} "$@"
    '';
  in {
    options.programs.oh-my-opencode = {
      enable = lib.mkEnableOption ''
        oh-my-opencode profile with isolated config at
        $XDG_CONFIG_HOME/oh-my-opencode.
      '';

      defaultConfigFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Seed opencode.jsonc into the profile on first run.";
      };

      openagentConfigFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Seed oh-my-openagent.json into the profile on first run.";
      };

      install = {
        claude = lib.mkOption {
          type = lib.types.enum ["no" "yes" "max20"];
          default = "no";
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
        };
      };
    };

    config = lib.mkIf cfg.enable {
      home.packages = [
        ohMyOpencodeWrapper
        opencodeOmoWrapper
      ];

      home.activation.setupOhMyOpencode = lib.hm.dag.entryAfter ["writeBoundary"] ''
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg omoOcDir}
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod 0750 ${lib.escapeShellArg omoOcDir}

        ${lib.optionalString (cfg.defaultConfigFile != null) ''
          if [ ! -e ${lib.escapeShellArg "${omoOcDir}/opencode.jsonc"} ]; then
            $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0640 ${cfg.defaultConfigFile} ${lib.escapeShellArg "${omoOcDir}/opencode.jsonc"}
          fi
        ''}

        ${lib.optionalString (cfg.openagentConfigFile != null) ''
          if [ ! -e ${lib.escapeShellArg "${omoOcDir}/oh-my-openagent.json"} ]; then
            $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0640 ${cfg.openagentConfigFile} ${lib.escapeShellArg "${omoOcDir}/oh-my-openagent.json"}
          fi
        ''}

        ${omoLib.mkInstallIfChanged {
          inherit pkgs;
          stampPath = installStamp;
          fingerprint = installFingerprint;
          prefix = "$DRY_RUN_CMD ";
          body = "env XDG_CONFIG_HOME=${lib.escapeShellArg omoConfigDir} ${omoBin} install ${installArgs}";
        }}

        if [ -f ${lib.escapeShellArg "${omoOcDir}/opencode.jsonc"} ]; then
          $DRY_RUN_CMD ${pkgs.gnused}/bin/sed -i \
            -e 's|"oh-my-openagent@latest"|"${pluginPath}"|g' \
            -e 's|"oh-my-opencode@latest"|"${pluginPath}"|g' \
            ${lib.escapeShellArg "${omoOcDir}/opencode.jsonc"}
        fi
      '';
    };
  };
}
