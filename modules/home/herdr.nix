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
#
# Plugins (herdr-navigator, herdr-auto-title) are installed per instance by
# the herdr-plugins-install oneshot below. They must be installed on EVERY
# server the owner's client can focus: a plugin_action keybind is looked up
# on the focused endpoint's server (src/client/shell/actions.rs answers
# "custom command is not available on this endpoint" otherwise), so a
# plugin installed only on one instance does nothing when a remote
# machine's workspace is focused.
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
      ++ lib.optionals cfg.integrations.antigravity ["antigravity-cli"]
      ++ lib.optionals cfg.integrations.hermes ["hermes"];
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

    # Drift-checked plugin install: `herdr plugin install` does not
    # overwrite, so a plugin already installed at a different ref (a manual
    # HEAD install, or a previous pin) is uninstalled first. Uninstall keeps
    # the plugin's config dir, and a new build keeps running until the
    # restart action replaces it.
    pluginsInstallScript = pkgs.writeShellScript "herdr-install-plugins" ''
      set -euo pipefail
      export PATH="${lib.makeBinPath [herdrPkg]}:$PATH"
      export HERDR_SOCKET_PATH=${lib.escapeShellArg apiSocket}

      install_plugin() {
        repo=$1
        ref=$2
        restart=$3
        want="github:$repo@$ref"
        installed=$(${herdrBin} plugin list 2>/dev/null | grep -o "github:$repo@[^] ]*" | head -1 || true)
        if [ "$installed" = "$want" ]; then
          echo "herdr plugins: $repo already at $ref"
          return 0
        fi
        if [ -n "$installed" ]; then
          echo "herdr plugins: $repo at '$installed' drifts from '$want'; reinstalling"
          ${herdrBin} plugin uninstall "$repo" || true
        fi
        ${herdrBin} plugin install --yes --ref "$ref" "$repo"
        if [ -n "$restart" ]; then
          # Plugins only start when the server starts, so a long-lived
          # plugin needs its restart action after the first install. A
          # failed restart is non-fatal: the next server start starts the
          # new build anyway.
          ${herdrBin} plugin action invoke "$restart" \
            || echo "herdr plugins: $repo installed but '$restart' failed; starts at the next server start" >&2
        fi
      }

      ${lib.concatMapStrings (p: ''
          install_plugin ${lib.escapeShellArg p.repo} ${lib.escapeShellArg p.ref} ${lib.escapeShellArg (p.restartAction or null)}
        '')
        cfg.plugins}
    '';

    # Toolchain the plugin manifests' [[build]] commands need, on the
    # oneshot's PATH: herdr-navigator builds with cargo (rustc + a C linker),
    # herdr-auto-title with go. Setting PATH on a unit REPLACES systemd's
    # default, so the basic dirs are appended as in herdr-web-ui's install.
    pluginBuildPath =
      "${lib.makeBinPath [herdrPkg pkgs.rustc pkgs.cargo pkgs.go pkgs.stdenv.cc]}"
      + ":/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin";
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
        hermes = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Install the Hermes Agent integration (plugin in
            ~/.hermes/plugins, enablement in ~/.hermes/config.yaml,
            restore floor v5). Requires ~/.hermes to exist first — the
            install fails with "hermes config directory not found" when
            hermes is not installed, so this stays off wherever the
            gateway does not run (p on charon, hermes-inspect only).
          '';
        };
      };

      # GitHub plugins installed per herdr instance. Server-side: a client
      # plugin_action keybind resolves on the focused endpoint's server, so
      # every machine the owner's client can focus needs the same list.
      # Install-time builds run against the network with this module's
      # buildDeps on PATH (herdr runs the plugin manifest's [[build]]).
      plugins = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            repo = lib.mkOption {
              type = lib.types.str;
              description = "GitHub owner/repo passed to `herdr plugin install`.";
            };
            ref = lib.mkOption {
              type = lib.types.str;
              description = ''
                Git ref passed as `herdr plugin install --ref`. Always pin a
                released tag, never HEAD: HEAD moves between deploys and the
                install is drift-checked against exactly this ref.
              '';
            };
            restartAction = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = ''
                Plugin action invoked after install, to start or replace the
                running instance. Plugins only start when the server starts,
                so a plugin with a long-lived process (herdr-auto-title) needs
                its restart action after the first install; on-demand plugins
                (herdr-navigator) spawn a pane per invocation and need none.
              '';
            };
          };
        });
        default = [
          # The fuzzy searcher (prefix+t): one navigator for workspaces,
          # agents, projects, sessions, remotes, directories and actions.
          {
            repo = "thanhdat77/herdr-navigator";
            ref = "v0.3.6";
          }
          # Names tabs/panes after the work in them; feeds the sidebar's
          # $topic token.
          {
            repo = "kryptamine/herdr-auto-title";
            ref = "v0.13.2";
            restartAction = "herdr.auto-title.restart";
          }
        ];
        description = ''
          Plugins installed on every herdr instance this profile owns.
          `herdr plugin install` does not overwrite, so the oneshot compares
          the installed source ref against the configured one and
          uninstalls first on drift.
        '';
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

      systemd.user.services.herdr-plugins-install = {
        Unit = {
          Description = "Install herdr plugins (herdr-navigator, herdr-auto-title)";
          After = ["herdr.service"];
        };
        Service = {
          Type = "oneshot";
          RemainAfterExit = true;
          # One network build per plugin (cargo/go against crates.io and the
          # Go module proxy), and deliberately no Restart: a boot loop when
          # GitHub is unreachable helps nobody.
          TimeoutStartSec = "30min";
          Environment = ["PATH=${pluginBuildPath}"];
          ExecStart = "${pluginsInstallScript}";
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
