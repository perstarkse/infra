_: {
  config.flake.nixosModules.codenomad = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.codenomad;
    defaultPackage = pkgs.callPackage ../../pkgs/codenomad {};
    serviceUser =
      if cfg.runAsMainUser
      then config.my.mainUser.name
      else cfg.user;
    serviceGroup =
      if cfg.runAsMainUser
      then lib.attrByPath ["users" "users" config.my.mainUser.name "group"] "users" config
      else cfg.group;
    extraFlags =
      [
        "--https"
        "false"
        "--http"
        "true"
        "--host"
        cfg.listenAddress
        "--http-port"
        (toString cfg.port)
        "--workspace-root"
        cfg.workspaceRoot
        "--log-level"
        cfg.logLevel
      ]
      ++ lib.optionals cfg.skipAuth ["--dangerously-skip-auth"]
      ++ lib.optionals cfg.unrestrictedRoot ["--unrestricted-root"];
  in {
    options.my.codenomad = {
      enable = lib.mkEnableOption "CodeNomad server";

      package = lib.mkOption {
        type = lib.types.package;
        default = defaultPackage;
        defaultText = lib.literalExpression "pkgs.callPackage ../../pkgs/codenomad {}";
        description = "Package containing the codenomad binary.";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "codenomad";
        description = "System user to run CodeNomad when runAsMainUser is false.";
      };

      group = lib.mkOption {
        type = lib.types.str;
        default = "codenomad";
        description = "System group to run CodeNomad when runAsMainUser is false.";
      };

      runAsMainUser = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Run CodeNomad as my.mainUser.name instead of a dedicated system user.";
      };

      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/codenomad";
        description = "Persistent data directory for CodeNomad.";
      };

      workspaceRoot = lib.mkOption {
        type = lib.types.str;
        default = "${cfg.dataDir}/workspaces";
        description = "Workspace root directory exposed by CodeNomad.";
      };

      manageWorkspaceRoot = lib.mkOption {
        type = lib.types.bool;
        default =
          cfg.workspaceRoot
          == (toString cfg.dataDir)
          || lib.hasPrefix "${toString cfg.dataDir}/" cfg.workspaceRoot;
        description = "Manage workspaceRoot ownership/permissions with tmpfiles.";
      };

      listenAddress = lib.mkOption {
        type = lib.types.str;
        default = config.my.listenNetworkAddress;
        description = "Address for CodeNomad to bind on.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 9898;
        description = "HTTP port for CodeNomad.";
      };

      logLevel = lib.mkOption {
        type = lib.types.str;
        default = "info";
        description = "CodeNomad log level.";
      };

      skipAuth = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Disable CodeNomad internal auth (intended behind wake-proxy).";
      };

      unrestrictedRoot = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Allow opening folders outside workspaceRoot.";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Open CodeNomad port in firewall.";
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

      systemd.tmpfiles.rules =
        [
          "d ${cfg.dataDir} 0750 ${serviceUser} ${serviceGroup} -"
        ]
        ++ lib.optionals cfg.manageWorkspaceRoot [
          "d ${cfg.workspaceRoot} 0750 ${serviceUser} ${serviceGroup} -"
        ];

      systemd.services.codenomad = {
        description = "CodeNomad Server";
        wantedBy = ["multi-user.target"];
        after = ["network-online.target"];
        wants = ["network-online.target"];
        environment.PATH = lib.mkForce "/home/p/.npm-global/bin:/home/p/.nix-profile/bin:/run/wrappers/bin:/run/current-system/sw/bin:/run/current-system/sw/sbin";

        serviceConfig = {
          Type = "simple";
          User = serviceUser;
          Group = serviceGroup;
          WorkingDirectory = cfg.dataDir;
          ExecStart = lib.concatStringsSep " " ([
              (lib.getExe cfg.package)
            ]
            ++ extraFlags);
          Restart = "always";
          RestartSec = "5s";

          NoNewPrivileges = true;
          PrivateTmp = true;
        };
      };

      networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [cfg.port];
    };
  };
}
