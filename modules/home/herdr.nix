# herdr on {charon,makemake}: the coding-agent execution surface.
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

    # Hold a logind sleep blocker while some agent reports `working`. Idle
    # agents do not block, so this does not defeat auto-suspend for an unused
    # session. auto-suspend already greps `systemd-inhibit --list` for sleep
    # blockers, so taking one here is the whole integration.
    #
    # LIMIT: max hold ${cfg.sleepInhibit.maxHoldSeconds}s. Agent status is
    # herdr-reported, so an agent that dies while still marked `working` would
    # hold the blocker forever and charon would never suspend again. After the
    # ceiling this gives up and waits for an agent to report idle again. Raise
    # it once herdr reports dead agents, or if a legitimate long run trips it.
    #
    # Fails open on purpose: an unreadable agent list counts as "nothing is
    # working", so a restarting or crashed server releases the blocker instead
    # of pinning the machine awake.
    inhibitScript = pkgs.writeShellScript "herdr-sleep-inhibit" ''
      set -uo pipefail
      socket="${apiSocket}"
      herdr=${herdrBin}
      inhibit=${lib.getExe' pkgs.systemd "systemd-inhibit"}
      date=${lib.getExe' pkgs.coreutils "date"}
      sleep=${lib.getExe' pkgs.coreutils "sleep"}
      grep=${lib.getExe' pkgs.gnugrep "grep"}
      interval=${toString cfg.sleepInhibit.intervalSeconds}
      max_hold=${toString cfg.sleepInhibit.maxHoldSeconds}

      inhibitor_pid=""
      held_since=0
      tripped=0

      release() {
        if [ -n "$inhibitor_pid" ]; then
          kill "$inhibitor_pid" 2>/dev/null || true
          wait "$inhibitor_pid" 2>/dev/null || true
          inhibitor_pid=""
          held_since=0
          echo "herdr-sleep-inhibit: released" >&2
        fi
      }
      trap release EXIT INT TERM

      while :; do
        working=$(
          HERDR_SOCKET_PATH="$socket" "$herdr" agent list 2>/dev/null |
            "$grep" -c '"agent_status":"working"' || true
        )
        now=$("$date" +%s)

        if [ "$working" -gt 0 ] && [ "$tripped" -eq 0 ]; then
          if [ -z "$inhibitor_pid" ]; then
            "$inhibit" --what=sleep --mode=block --who=herdr-agent \
              --why="herdr agent working" "$sleep" infinity &
            inhibitor_pid=$!
            held_since=$now
            echo "herdr-sleep-inhibit: holding (agent working)" >&2
          elif [ $((now - held_since)) -ge "$max_hold" ]; then
            tripped=1
            release
            echo "herdr-sleep-inhibit: max hold ''${max_hold}s reached; not blocking until an agent goes idle" >&2
          fi
        elif [ "$working" -eq 0 ]; then
          tripped=0
          release
        fi

        "$sleep" "$interval"
      done
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
          for every client.
        '';
      };

      sleepInhibit = {
        enable = lib.mkEnableOption "block logind sleep while a herdr agent is working";
        intervalSeconds = lib.mkOption {
          type = lib.types.int;
          default = 5;
          description = "How often to re-read the agent list.";
        };
        maxHoldSeconds = lib.mkOption {
          type = lib.types.int;
          default = 1800;
          description = ''
            Give up on blocking sleep after this long without an agent ever
            going idle. See the LIMIT note on the script for why.
          '';
        };
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
          # Pin the socket so the server and this user's clients resolve the
          # same path even if a desktop session exports a different
          # XDG_CONFIG_HOME.
          # Plugins that need more of the server's environment add to
          # systemd.user.services.herdr.Service.Environment directly: Home
          # Manager merges those lists across modules.
          # __NIXOS_SET_ENVIRONMENT_DONE must be present but EMPTY — see the
          # note on the option below; a set guard makes panes spawned by this
          # server skip NixOS env setup and lose ~/.nix-profile/bin.
          Environment = [
            "HERDR_SOCKET_PATH=${apiSocket}"
            "__NIXOS_SET_ENVIRONMENT_DONE="
          ];
          ExecStart = "${herdrBin} server";
          Restart = "always";
          RestartSec = 5;
        };
        # WantedBy default.target: without it Home Manager links the file but
        # nothing ever starts it (verified on makemake 2026-10-11: the unit
        # was absent from default.target.wants while the server only ran as
        # stray remote-client-bridge children).
        Install.WantedBy = ["default.target"];
      };

      # Clients inherit the same pin, so a plain `herdr …` in any shell of
      # this user attaches to the running server instead of starting one.
      home.sessionVariables = {
        HERDR_SOCKET_PATH = apiSocket;
      };

      # Rerun when the flake input moves OR pi-agent's files change: a new
      # herdr rev may bump integration versions, and the install must land in
      # the directory pi actually loads.
      systemd.user.services.herdr-integrations = {
        Unit = {
          Description = "Install herdr agent integrations (pi, antigravity-cli)";
          After = ["herdr.service"];
          X-Restart-Triggers = [herdrPkg] ++ lib.optional piAgentEnabled "${piAgentConfigDir}/.hm-revision";
        };
        Service = {
          Type = "oneshot";
          RemainAfterExit = true;
          # herdr.service restarts with a 5s delay, so an install racing the
          # first start retries briefly — then succeeds with a warning rather
          # than failing the unit and blocking the bridge [[startup]] hook.
          ExecStart = pkgs.writeShellScript "herdr-integrations-wrapped" ''
            set -uo pipefail
            for _ in $(seq 1 12); do
              if ${integrationScript} 2>&1; then exit 0; fi
              sleep 5
            done
            echo "herdr-integrations: server never answered; leaving integrations uninstalled" >&2
            exit 0
          '';
        };
        Install.WantedBy = ["default.target"];
      };

      systemd.user.services.herdr-sleep-inhibit = lib.mkIf cfg.sleepInhibit.enable {
        Unit = {
          Description = "Block logind sleep while a herdr agent is working";
          After = ["herdr.service"];
        };
        Service = {
          Type = "simple";
          ExecStart = inhibitScript;
          Restart = "on-failure";
          RestartSec = 5;
        };
        Install.WantedBy = ["default.target"];
      };
    };
  };
}
