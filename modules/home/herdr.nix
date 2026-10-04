# herdr on charon: the coding-agent execution surface.
#
# herdr is server + attached clients: panes and agents live in the server and
# clients attach/detach. `herdr server stop` ends the session AND its panes,
# so the server is a lingering user service, not a per-shell start.
#
# Findings from source (upstream herdrdev/herdr @ bce28752, herdr 0.9.3 —
# src/main.rs, src/server/headless*, src/cli/server.rs, src/session.rs,
# src/config/io.rs, src/server/socket_paths.rs), all verified by reading, not
# docs:
# - The long-running server is `herdr server` (no subcommand): main.rs routes
#   args[1]=="server" to server::headless::run_server(), a Type=simple process.
# - No self-daemonise: a second `herdr server` on a live socket prints
#   "error: herdr server is already running" and exits 1. Restart=always is
#   therefore safe; no RestartPreventExitStatus=78 — herdr has no exit(78)
#   anywhere in src/, on any rev checked.
# - State + sockets live under ~/.config/herdr (config_dir()), NOT the
#   XDG runtime dir: herdr.sock and herdr-client.sock sit next to config.toml.
#   XDG_RUNTIME_DIR needs no override; HOME must be right (it is, user unit).
# - HERDR_ENV=1 only marks processes herdr spawned (nested-herdr guard);
#   never set it on the service itself.
# - Session restore is native (server persists panes); a restart resumes them.
# - Bundled integrations ship ahead of the floors for native restore:
#   pi v9 (floor 2), antigravity-cli v3 (floor 1).
{
  config.flake.homeModules.herdr = {
    lib,
    pkgs,
    config,
    ...
  }: let
    cfg = config.my.herdr;
    herdrPkg = cfg.package;
    herdrBin = lib.getExe herdrPkg;

    piAgentConfigDir =
      lib.attrByPath ["my" "agentTooling" "pi-agent" "configDir"]
      "${config.home.homeDirectory}/.pi/agent"
      config;
    piAgentEnabled =
      lib.attrByPath ["my" "agentTooling" "pi-agent" "enable"] false config;

    socketDir = "${cfg.socketDir}";
    apiSocket = "${socketDir}/herdr.sock";
    clientSocket = "${socketDir}/herdr-client.sock";

    # herdr chmods both sockets 0600 (src/server/socket_paths.rs) and exposes
    # no knob for it, so sharing means applying an ACL AFTER the bind. With
    # Type=simple systemd considers the unit started before the socket exists,
    # hence the wait. Never fails the unit: a missing socket is a warning to
    # read in the journal, not a reason to kill a healthy server.
    # ponytail: no path unit; a herdr restart re-runs ExecStartPost, which
    # re-ACLs. Add a watcher if herdr ever rebinds without a service restart.
    shareScript = pkgs.writeShellScript "herdr-share-sockets" ''
      set -uo pipefail
      api="$1"
      client="$2"
      shift 2
      for _ in $(seq 1 60); do
        [ -S "$api" ] && break
        sleep 0.5
      done
      if [ ! -S "$api" ]; then
        echo "herdr: $api never appeared; socket not shared with: $*" >&2
        exit 0
      fi
      for path in "$api" "$client"; do
        [ -S "$path" ] || continue
        for user in "$@"; do
          ${pkgs.acl}/bin/setfacl -m "u:$user:rw" "$path" \
            || echo "herdr: setfacl failed for $user on $path" >&2
        done
      done
      echo "herdr: sockets shared with: $*"
    '';

    # Install AFTER pi-agent laid down ~/.pi/agent: herdr creates the
    # extensions dir only when the agent dir already exists, and the pi
    # integration resolves its target via PI_CODING_AGENT_DIR → ~/.pi/agent.
    integrationTargets =
      ["pi"]
      ++ lib.optionals cfg.integrations.antigravity ["antigravity-cli"];
    integrationScript = pkgs.writeShellScript "herdr-install-integrations" ''
      set -euo pipefail
      export PATH="${lib.makeBinPath [herdrPkg]}:$PATH"
      ${lib.optionalString (piAgentEnabled && cfg.integrations.pi) ''
        ${lib.optionalString (cfg.piAgentDir != null) "export PI_CODING_AGENT_DIR=${lib.escapeShellArg cfg.piAgentDir}"}
      ''}
      for target in ${lib.escapeShellArgs integrationTargets}; do
        ${herdrBin} integration install "$target"
      done
    '';
  in {
    options.my.herdr = {
      enable = lib.mkEnableOption "herdr coding-agent execution surface (server + integrations)";

      package = lib.mkOption {
        type = lib.types.package;
        example = lib.literalExpression "ctx.inputs.herdr.packages.\${pkgs.stdenv.hostPlatform.system}.default";
        description = "herdr package. No default: the enabling machine sets it from the locked herdr flake input (home modules cannot see flake inputs).";
      };

      piAgentDir = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/home/p/.pi/agent";
        description = "PI_CODING_AGENT_DIR for the pi integration install. Null (default) leaves the env unset so herdr resolves ~/.pi/agent itself.";
      };

      integrations = {
        pi = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Install the pi integration (agent lifecycle state via extension, bundled v9, restore floor v2).";
        };
        antigravity = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Install the antigravity-cli integration (hooks into ~/.gemini/config, bundled v3, restore floor v1).";
        };
      };

      socketDir = lib.mkOption {
        type = lib.types.str;
        default = "${config.home.homeDirectory}/.config/herdr";
        defaultText = "<\${HOME}>/.config/herdr";
        description = ''
          Directory holding herdr.sock and herdr-client.sock. This is herdr's
          own default (config_dir() = $XDG_CONFIG_HOME/herdr, else
          $HOME/.config/herdr); override only if you also pin HERDR_SOCKET_PATH
          for every client. Any machine config that hands the socket to another
          user must repeat this path.
        '';
      };

      shareWith = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["agent"];
        description = ''
          Local users to grant read/write on the herdr sockets, so they can
          drive the server as a client (`herdr agent list`, TUI attach) without
          owning it. The server keeps running as the Home Manager user, which
          is deliberate: panes are spawned by the server, so an agent-owned
          server would run pi and agy as `agent` — and ~/.pi/agent is 0700
          owned by this user, so those panes would silently come up with an
          empty agent config. Sharing the socket instead gives the second user
          the client surface without moving the spawn identity.
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      # Binary is also expected in the machine's environment.systemPackages:
      # that is what puts `herdr` on the default ssh PATH for the `agent`
      # user, which the non-login ssh command line cannot get from a Home
      # Manager profile.
      systemd.user.services.herdr = {
        Unit = {
          Description = "herdr coding-agent server";
          After = ["network.target"];
        };
        Service = {
          Type = "simple";
          # Pin the socket so the server, this user's clients, and anyone the
          # socket is shared with all resolve the same path even if a desktop
          # session exports a different XDG_CONFIG_HOME.
          Environment = "HERDR_SOCKET_PATH=${apiSocket}";
          ExecStart = "${herdrBin} server";
          ExecStartPost = lib.concatStringsSep " " [
            (lib.escapeShellArg shareScript)
            (lib.escapeShellArg apiSocket)
            (lib.escapeShellArg clientSocket)
            (lib.escapeShellArgs cfg.shareWith)
          ];
          Restart = "always";
          RestartSec = 5;
        };
        Install.WantedBy = ["default.target"];
      };

      # Clients inherit the same pin, so a plain `herdr …` in any shell of
      # this user attaches to the running server instead of starting one.
      home.sessionVariables = lib.optionalAttrs (cfg.shareWith != []) {
        HERDR_SOCKET_PATH = apiSocket;
      };

      # Rerun when the flake input moves OR pi-agent's files change: a new
      # herdr rev may bump integration versions, and the install must land in
      # the directory pi actually loads. (No After on home-manager: HM
      # activation writes the files before user units start on next login,
      # and X-Restart-Triggers restarts this unit when they change.)
      systemd.user.services.herdr-integrations = {
        Unit = {
          Description = "Install herdr agent integrations (pi, antigravity-cli)";
          After = ["herdr.service"];
          X-Restart-Triggers = [herdrPkg] ++ lib.optional piAgentEnabled "${piAgentConfigDir}/.hm-revision";
        };
        Service = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = integrationScript;
        };
        Install.WantedBy = ["default.target"];
      };
    };
  };
}
