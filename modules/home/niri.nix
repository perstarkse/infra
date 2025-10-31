{
  config.flake.homeModules.niri = {
    pkgs,
    lib,
    osConfig,
    config,
    ...
  }: let
    guiCfg = osConfig.my.gui;
    cfg = lib.attrByPath ["my" "niri"] {} config;
    workspaceNamesDefault = [
      "1:main"
      "2:web"
      "3:code"
      "4:chat"
      "5:media"
      "6:games"
      "7:build"
      "8:vm"
      "9:misc"
      "10:scratch"
    ];
    workspaceNames = cfg.workspaceNames or workspaceNamesDefault;
    workspaceCount = builtins.length workspaceNames;
    workspaceCountStr = builtins.toString workspaceCount;
    firstWorkspace =
      if workspaceCount == 0
      then ""
      else builtins.head workspaceNames;
    setupWorkspaces = pkgs.writeShellScriptBin "niri-setup-workspaces" ''
      #!/usr/bin/env bash
      set -euo pipefail

      # Wait for niri IPC to become accessible before configuring workspaces.
      for _ in $(seq 1 40); do
        if niri msg --json outputs >/dev/null 2>&1; then
          break
        fi
        sleep 0.1
      done

      if [ ${workspaceCountStr} -eq 0 ]; then
        exit 0
      fi

      index=1
      for name in ${lib.concatMapStringsSep " " lib.escapeShellArg workspaceNames}; do
        niri msg action focus-workspace "$index" >/dev/null 2>&1 || true
        niri msg action set-workspace-name "$name" >/dev/null 2>&1 || true
        index=$((index + 1))
      done

      if [ -n "${firstWorkspace}" ]; then
        niri msg action focus-workspace ${lib.escapeShellArg firstWorkspace} >/dev/null 2>&1 || true
      fi
    '';
    wallpaper = ../../wallpaper-2.jpg;
  in {
    options.my.niri = {
      workspaceNames = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = workspaceNamesDefault;
        description = ''
          Ordered list of persistent workspace names used by the niri session.
          These names should match any shortcuts in niri-config.kdl and Waybar formatting.
        '';
      };

      workspaceIcons = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {};
        description = ''
          Optional icon mapping keyed by workspace name for use in the Waybar workspace indicator.
          Provide values compatible with the fonts available in your bar.
        '';
      };
    };

    config = lib.mkIf (guiCfg.enable && guiCfg.session == "niri") {
      home.packages =
        (with pkgs; [
          wofi
          grim
          slurp
          wl-clipboard
          dunst
        ])
        ++ [setupWorkspaces];

      home.activation.niriSetupWorkspaces = lib.hm.dag.entryAfter ["writeBoundary"] ''
        ${setupWorkspaces}/bin/niri-setup-workspaces || true
      '';

      # stylix.targets.niri.enable = lib.mkDefault true;

      xdg.configFile."niri/config.kdl".source = ./niri-config.kdl;

      systemd.user.services.swaybg = {
        Unit = {
          Description = "Set wallpaper via swaybg for the Niri session";
          PartOf = ["graphical-session.target"];
          After = ["graphical-session.target"];
        };
        Install = {
          WantedBy = ["graphical-session.target"];
        };
        Service = {
          ExecStart = "${pkgs.swaybg}/bin/swaybg -i ${wallpaper} -m fill";
          Restart = "on-failure";
        };
      };
    };
  };
}
