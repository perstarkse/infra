# Personal agent: Hermes Agent on makemake, running NATIVELY as `agent`.
#
# Upstream ships `nixosModules.default`; this module is the fleet wrapper that
# pins the pieces the generic module deliberately leaves open:
#
#   - Native, not container (roadmap Phase D). The container only walled off the
#     gateway, not the work, and once panes run as `agent` on the host the LLM
#     already executes arbitrary code there. Container mode is not offered as an
#     option: its plumbing (the /data mount, the /opt symlink farm) is gone, so
#     a flag to turn it back on would only select a broken deployment.
#   - stateDir IS the agent's home. Native mode sets HOME = stateDir, so
#     setting it to /home/agent is what makes the gateway an ordinary user of
#     the machine instead of a service with a private root: ssh, himalaya and
#     herdr all resolve the same paths a login shell would.
#   - the gateway runs as the fleet `agent` account, NOT a `hermes` one. The
#     user is created by agent-ssh-access, so upstream's createUser is off —
#     which also means upstream's `linger` default (it lives inside the
#     createUser block) never applies, and cron would silently degrade to
#     unscoped workers. It is set explicitly below.
#   - the fleet SSH private key and a GitHub known_hosts land in that same
#     home, so `restrict`-ed key auth never prompts.
#   - the gateway API port stays gated to the io router. Native mode binds the
#     host directly, so this is no longer about --network=host; the port is
#     still LAN-reachable and must stay restricted.
#   - himalaya and wake-charon ride `services.hermes-agent.extraPackages`
#     ("more packages on the PATH of the agent"), which upstream also mirrors
#     into users.users.<user>.packages. In container mode these needed
#     container-bin symlinks and :ro bind mounts instead; native mode does not.
#
# Why putting the gateway's writable state inside the agent's home is safe:
# Home Manager does not write its files INTO the home, it links them there
# from /nix/store, root-owned. Verified on makemake: ~/.config/systemd/user/
# herdr.service and ~/.ssh/conf.d/herdr-mesh are both symlinks into the store.
# The agent can create and delete anything it likes under its own home and
# still cannot modify a single Home Manager-managed byte.
{inputs, ...}: {
  config.flake.nixosModules.hermes = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.hermes;
    inherit (cfg) stateDir;
    agentUser = config.services.hermes-agent.user;
    # The account that actually drives the fleet. The fleet SSH key and
    # known_hosts belong to `agent`, not to the hermes service user: once herdr
    # runs as `agent` (roadmap Phase C), `agent` is the identity that reaches
    # the other machines, and the gateway only ever borrowed the key. Taken from
    # the agent-ssh-access options rather than hardcoded so the two accounts'
    # home paths cannot drift (that module's `home` IS
    # users.users.<user>.home).
    fleetUser = config.my.agent-ssh-access.user or "agent";
    fleetHome = config.my.agent-ssh-access.home or "/home/agent";
    envFile = config.my.secrets.getPath cfg.envSecretName "env";
    sshKeyFile = config.my.secrets.getPath cfg.sshKeySecretName "private_key";
    # Re-render $HERMES_HOME/.env from the secret, then restart BOTH consumers
    # (the gateway and the signal-cli daemon, which reads SIGNAL_ACCOUNT from
    # the same file), so the two can never end up on different account numbers.
    #
    # The re-render must live INSIDE this script, not as a second ExecStart:
    # systemd runs ExecStart lines through separate shells with `;` semantics,
    # so `render && restart` in ExecStart and a failure in render would be
    # masked by the restart's exit code. One script, one shell, set -euo.
    #
    # Upstream gives no rotation handling at all (no systemd.paths, no
    # restartTriggers — and restartTriggers on /run/secrets paths would never
    # fire anyway: the units are byte-identical across content rotations, same
    # reason ntfy-sh and gatus watch the file). Hand-written rather than spread
    # from mkTryRestartOnRotation because that helper restarts exactly one
    # service and would collide with this module's own `systemd.services`
    # definitions.
    #
    # try-restart first, then start: a daemon that is *stopped* (e.g. because
    # its secret was missing and it exhausted its start limit) is only brought
    # up by the start fallback.
    # Signal FIRST, then the agent: the gateway dials signal-cli during its own
    # startup and logs "Signal: cannot reach signal-cli" if the daemon is not
    # listening yet. Restarting the agent first guaranteed that race on every
    # rotation (observed live: 13:58:55, one restart after the secret landed).
    restartUnitsScript = pkgs.writeShellScript "hermes-env-restart-units" ''
      set -euo pipefail
      target="${stateDir}/.hermes/.env"
      install -d -m 0700 -o ${agentUser} -g ${agentUser} "$(dirname "$target")"
      tmp=$(mktemp)
      for src in ${lib.escapeShellArgs [envFile]}; do
        cat "$src" >> "$tmp"
      done
      install -m 0600 -o ${agentUser} -g ${agentUser} "$tmp" "$target"
      rm -f "$tmp"
      echo "hermes: re-rendered $target from ${envFile}"
      # getExe' takes the binary name: plain lib.getExe pkgs.systemd already
      # returns .../bin/systemctl, and appending /systemctl to THAT produced
      # .../bin/systemctl/systemctl -> status 127 on every rotation.
      for unit in signal-cli.service hermes-agent.service; do
        ${lib.getExe' pkgs.systemd "systemctl"} try-restart "$unit" \
          || ${lib.getExe' pkgs.systemd "systemctl"} start "$unit"
      done
    '';
  in {
    imports = [inputs.hermes-agent.nixosModules.default];

    options.my.hermes = {
      enable = lib.mkEnableOption "Hermes Agent (personal agent runtime)";

      stateDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/hermes";
        description = ''
          Agent state root. Holds HERMES_HOME (${stateDir}/.hermes), the
          workspace, and the SSH identity. Keep it on local disk, not mergerfs:
          the session DB is SQLite.
        '';
      };

      envSecretName = lib.mkOption {
        type = lib.types.str;
        default = "hermes-env";
        description = "vars generator providing the KEY=VALUE environment file.";
      };

      sshKeySecretName = lib.mkOption {
        type = lib.types.str;
        default = "agent-ssh-key";
        description = "vars generator providing private_key for fleet SSH.";
      };

      exposeFleetSshKey = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Copy the fleet SSH private key and a GitHub known_hosts into the
          agent's home so it can reach the other machines and GitHub without a
          prompt.
        '';
      };

      mail = {
        enable = lib.mkEnableOption "himalaya mail access for the agent";

        secretName = lib.mkOption {
          type = lib.types.str;
          default = "hermes-mail";
          description = "vars generator holding the himalaya config.toml.";
        };

        configFile = lib.mkOption {
          type = lib.types.str;
          default = "config.toml";
          description = "File inside secretName's output carrying the himalaya config.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.himalaya;
          defaultText = lib.literalExpression "pkgs.himalaya";
          description = ''
            Himalaya package. Handed to the gateway through
            services.hermes-agent.extraPackages, which also mirrors it into
            users.users.<user>.packages, so the agent has it on its interactive
            PATH too.
          '';
        };
      };

      model = lib.mkOption {
        type = lib.types.str;
        default = "anthropic/claude-sonnet-4";
        description = ''
          Model id for the default provider.

          When modelProvider is set, this is the BARE model id the endpoint
          expects — not a `provider/model` pair. Hermes splits `model.default`
          with split_model_config_default(): it only understands an explicit
          provider beside the id. Writing `custom:commandcode/meta/muse-…`
          instead makes it strip just the `custom:` prefix and send
          `commandcode/meta/muse-…` on the wire, which the endpoint rejects
          with `400 … is not a valid model ID`.
        '';
      };

      modelProvider = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Provider to route the model through, written as `model.provider`.
          null keeps the provider implicit (OpenRouter-style `provider/model`
          strings in `model`).
        '';
      };

      baseUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Provider base URL. null keeps the provider default (OpenRouter).";
      };

      customProvider = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Name of a custom OpenAI-compatible provider to register in
          `providers:`. Hermes supports these natively — no plugin needed. The
          entry becomes `custom:<name>`, which is the prefix `model` must then
          use, and Hermes derives the credential env var from the name:
          `HERMES_CUSTOM_<NAME>_API_KEY` (non-alphanumerics → `_`, uppercased),
          so `commandcode` → `HERMES_CUSTOM_COMMANDCODE_API_KEY`.

          null registers nothing and uses a built-in provider (OpenRouter by
          default).
        '';
      };

      credentialEnvVar = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Env var holding this custom provider's credential, instead of letting
          Hermes derive HERMES_CUSTOM_<NAME>_API_KEY from the provider name.

          Set it when the credential already lives under another name (the
          agent env file may well already carry it) — this avoids rewriting a
          secret just to match a naming convention.
        '';
      };

      apiMode = lib.mkOption {
        type = lib.types.str;
        default = "chat_completions";
        description = ''
          Transport for a custom provider: chat_completions |
          anthropic_messages | codex_responses. Only used when customProvider
          is set.
        '';
      };

      reasoningEffort = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = ''
          Global reasoning effort: minimal | low | medium | high | xhigh | max |
          ultra, or "" for the model default.

          This belongs in `agent.reasoning_effort`, NOT on the provider entry —
          `reasoning_effort` is not in Hermes' known provider keys, so putting it
          there is silently dropped with an "unknown config keys ignored"
          warning. Resolution order is per-model override first, then this
          global value (hermes_constants.py:resolve_reasoning_config).
        '';
      };

      reasoningModelOverrides = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = ''
          Per-model effort overrides, keyed by the full model id (e.g.
          "custom:commandcode/meta/muse-spark-1.3-contributor"). Takes
          precedence over reasoningEffort.
        '';
      };

      modelOverrides = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = ''
          Per-model metadata for models Hermes does not know, keyed by provider
          then model id:

            { "custom:commandcode"."meta/muse-spark-1.3-contributor" = {
                context_window = 1048576; supports_reasoning = true; }; }

          Without this an unknown id is assumed to be 200K context and
          vision/reasoning support stays unknown (fail-open), which is safe but
          under-reports the real window.
        '';
      };

      firewallPort = lib.mkOption {
        type = lib.types.port;
        default = 8642;
        description = ''
          Gateway API server port (API_SERVER_PORT, default 8642 upstream).
          It binds 127.0.0.1 by default, but container mode shares the host
          network, so the port is gated to the router anyway: a later
          API_SERVER_HOST change must not publish it to the LAN.

          The server itself is enabled via API_SERVER_ENABLED=true +
          API_SERVER_KEY=… in hermes-env (see vars/generators/hermes-env.nix),
          not via Nix — the key must never enter the store.
        '';
      };

      firewallAllowedSources = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["10.0.0.1"];
        description = "Sources allowed to reach firewallPort. io proxies everything else.";
      };
    };

    config = lib.mkIf cfg.enable (lib.mkMerge [
      {
        # The gateway installs its own files (fleet SSH key, known_hosts,
        # himalaya config) under fleetHome and runs as fleetUser. Both only work
        # if that account has a real, writable home — which agent-ssh-access
        # gates behind `createHome`. Fail here, at eval, with a sentence, rather
        # than at deploy with an EACCES from an installer.
        assertions = [
          {
            assertion = config.users.users.${fleetUser}.createHome or false;
            message = "my.hermes: the gateway runs as ${fleetUser} and installs its fleet SSH key and known_hosts under ${fleetHome}, but that account's home is not created. Set my.agent-ssh-access.createHome = true, or point my.hermes.stateDir somewhere writable.";
          }
          {
            # stateDir is what native mode sets HOME to. If it is not the user's
            # home, ssh/himalaya/herdr resolve one tree while the installers
            # write another, and nothing fails loudly.
            assertion = cfg.stateDir == fleetHome;
            message = "my.hermes.stateDir (${cfg.stateDir}) must equal my.agent-ssh-access.home (${fleetHome}): native mode sets HOME = stateDir, so any other value splits the agent's files across two trees.";
          }
        ];

        services.hermes-agent = {
          inherit (cfg) enable;
          # One stateDir, not two. `my.hermes.stateDir` and
          # `services.hermes-agent.stateDir` are separate options that only
          # coincided because both default to /var/lib/hermes; this makes the
          # machine's value authoritative for both.
          inherit (cfg) stateDir;
          # The gateway IS the agent. Upstream defaults to a `hermes` service
          # user; createUser is off because agent-ssh-access already owns that
          # account (and would fight upstream over `home` and `createHome`).
          #
          # Consequence, spelled out because it is silent: upstream's
          # `linger = mkDefault (!container.enable)` lives INSIDE the createUser
          # block, so switching it off also switches off the user bus that
          # restart-safe cron dispatch needs. Set explicitly further down.
          # Native, always. Roadmap Phase D retired container mode rather than
          # leaving it selectable: the container's whole reason for existing was
          # a stable /data bind mount and an /opt symlink farm, and with the
          # gateway running as `agent` in its own home all of that is just the
          # home. Offering the flag back would offer a mode whose plumbing no
          # longer exists — himalaya, wake-charon and the herdr client all
          # arrived through paths that are gone.
          container.enable = false;
          user = fleetUser;
          group = fleetUser;
          createUser = false;
          addToSystemPackages = true;

          # The agent's own tools. Upstream puts these on the service PATH and
          # mirrors them into users.users.<user>.packages. This is what replaces
          # the container-bin symlinks and :ro mounts native mode does not need.
          extraPackages =
            lib.optional cfg.mail.enable cfg.mail.package
            ++ lib.optional config.my.wake-charon.enable config.my.wake-charon.package;

          # Merged into $HERMES_HOME/.env on every activation, so a rotated key
          # needs a gateway restart, not a container rebuild.
          environmentFiles = [envFile];

          settings = {
            model =
              {
                default = cfg.model;
              }
              // lib.optionalAttrs (cfg.modelProvider != null) {provider = cfg.modelProvider;}
              // lib.optionalAttrs (cfg.baseUrl != null) {base_url = cfg.baseUrl;};

            # Custom OpenAI-compatible endpoint. Native support, not a plugin.
            # snake_case keys, not camelCase: Hermes auto-maps camelCase but
            # logs a warning for every key, and the provider entry's key set
            # (_KNOWN_PROVIDER_KEYS) is snake_case.
            providers = lib.optionalAttrs (cfg.customProvider != null) {
              "custom:${cfg.customProvider}" =
                {
                  "base_url" = cfg.baseUrl;
                  "api_mode" = cfg.apiMode;
                }
                // lib.optionalAttrs (cfg.credentialEnvVar != null) {
                  key_env = cfg.credentialEnvVar;
                };
            };

            model_overrides = cfg.modelOverrides;

            agent =
              {
                reasoning_effort = cfg.reasoningEffort;
              }
              // lib.optionalAttrs (cfg.reasoningModelOverrides != {}) {
                reasoning_overrides = cfg.reasoningModelOverrides;
              };
            toolsets = ["all"];
            # Non-sudo by construction, so there is no `sudo *` rule here: the
            # `agent` fleet account holds no sudo rule at all, which is the real
            # boundary, and denying sudo outright also blocked the container-mode
            # self-modification (apt/pip/npm via the NOPASSWD rule the upstream
            # container entrypoint provisions) that container mode was chosen for.
            # Container-internal sudo is namespaced to the container filesystem;
            # the host's /etc is not mounted and the store is read-only.
            approvals = {
              mode = "smart";
              # Unattended surfaces fail closed instead of waiting out an
              # approval timeout with no human on the other end.
              cron_mode = "deny";
              single_query_mode = "deny";
              unattended_mode = "deny";
              deny = [
                "git push --force*"
                "git push *main*"
                "git push *master*"
                "mkfs*"
                "dd if=* of=/dev/*"
                "*curl*|*sh*"
                "*wget*|*sh*"
              ];
            };
          };

          # Explicit even though it matches the module default: the whole backup
          # story assumes the workspace is inside the snapshotted path.
          workingDirectory = "${stateDir}/workspace";

          hermesHomeFiles."SOUL.md" = ./hermes/SOUL.md;

          restart = "always";
          restartSec = 5;
        };

        # The gateway's account is the fleet `agent`, which agent-ssh-access
        # already owns (hence createUser = false above).
        users.users.${fleetUser} = {
          # Restart-safe cron dispatch runs each job as `systemd-run --user
          # --scope`, which needs /run/user/<uid>/bus. A system service gets none
          # unless the uid lingers, and the dispatch then fails closed --
          # silently, with no failed job to grep for. Upstream would have
          # defaulted this, but its default sits INSIDE its createUser block,
          # which is off here. mkDefault so a machine can still override.
          linger = true;
          # stateDir IS this user's home (native mode sets HOME = stateDir), so
          # upstream's tmpfiles rule `d <stateDir> 2770 <user> <group>` and the
          # NixOS users-groups activation both own this directory's mode --
          # 2770 versus homeMode's 700. tmpfiles only runs at boot, so without
          # this the home would silently flip between 0700 after a switch and
          # 2770 after a reboot. Make the two agree rather than pick a winner.
          # The group is the user's own and holds nobody else, so 2770 grants
          # nothing extra.
          homeMode = lib.mkIf (cfg.stateDir == fleetHome) "2770";
        };

        my.secrets.allowReadAccess =
          [
            {
              # ONE entry per path: my.secrets generates a single ACL unit per
              # path (the unit name is derived from the path alone), so a second
              # entry for the same file declared elsewhere silently loses. That
              # is exactly how the signal-cli daemon ended up with a readers
              # list of only ["hermes"] and could not read the file it reads its
              # account number from. Every consumer of hermes-env goes here.
              # The gateway is `agent` now (roadmap Phase D), so `hermes` is no
              # longer a reader of anything here. signal-cli keeps its own
              # grant: it reads SIGNAL_ACCOUNT out of the same file and stays
              # its own system user.
              readers = [fleetUser "signal-cli"];
              path = envFile;
            }
          ]
          ++ lib.optional cfg.exposeFleetSshKey {
            readers = [fleetUser];
            path = sshKeyFile;
          };

        # Rotate hermes-env → the restart script re-renders .env, then restarts
        # BOTH consumers (the gateway and the signal-cli daemon, which reads
        # SIGNAL_ACCOUNT from the same file). Details live on restartUnitsScript.
        systemd.paths.hermes-env-rotation = {
          description = "Restart the agent when hermes-env rotates";
          wantedBy = ["multi-user.target"];
          pathConfig = {
            PathChanged = [envFile];
            Unit = "hermes-env-rotation-restart.service";
            TriggerLimitIntervalSec = "30s";
            TriggerLimitBurst = 10;
          };
        };
        systemd.services.hermes-env-rotation-restart = {
          description = "Re-render .env and restart the agent's consumers";
          serviceConfig = {
            Type = "oneshot";
            # Let a multi-file Clan write batch settle before the restarts fire.
            ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
            ExecStart = restartUnitsScript;
          };
        };
      }

      (lib.mkIf cfg.exposeFleetSshKey {
        my.secrets.exposeUserSecrets = [
          {
            enable = true;
            # The fleet key now belongs to `agent`, not `hermes` (roadmap D7 +
            # Phase E). Once the herdr server and the toolchain run as `agent`,
            # `agent` is the identity that actually reaches the other machines —
            # the gateway was only ever a borrower. Phase D moves the gateway to
            # the same account, so this stops being a second reader rather than
            # becoming a stale grant.
            user = fleetUser;
            secretName = cfg.sshKeySecretName;
            file = "private_key";
            # The account's own HOME. `stateDir` was only ever the container's
            # HOME, and the mesh config on both machines points at
            # ~/.ssh/id_ed25519.
            dest = "${fleetHome}/.ssh/id_ed25519";
            mode = "0400";
          }
        ];

        # Host keys for non-interactive `restrict`ed key auth. This has to land
        # in the driving account's own $HOME/.ssh — its home is
        # ${fleetHome}, and its own mesh config asks ssh to use
        # ~/.ssh/id_ed25519 from exactly here. It used to target the
        # container's HOME (${sshDir}); Phase E moved it with the key.
        # Fleet keys collected with ssh-keyscan over the LAN on 2026-09-29;
        # github's is the same key the workstation pins in programs.ssh.knownHosts
        # (modules/system/shared.nix).
        systemd.services.hermes-install-known-hosts = {
          description = "Install the agent's known_hosts into its \$HOME/.ssh";
          wantedBy = ["multi-user.target"];
          after = ["local-fs.target"];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            set -euo pipefail
            install -d -m 0700 -o ${fleetUser} -g ${fleetUser} ${fleetHome}/.ssh
            install -m 0644 -o ${fleetUser} -g ${fleetUser} /dev/stdin ${fleetHome}/.ssh/known_hosts <<'KNOWN_HOSTS'
            github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
            charon.lan,10.0.0.15 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINysM9VHtOcjYDAZCTuJl+hjNNHlFExmDx5J7o40Vljh
            10.0.0.1 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMPugZkqgjBKletbzaNipPLSrq5+ToQFBLyCojQLD8pt
            10.0.0.10 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMLhhyxdh0dr+tfcyBgv9K0s5nK9mfwOENBnFVteZOB9
            KNOWN_HOSTS
          '';
        };
      })

      (lib.mkIf cfg.mail.enable (let
        mailSrc = config.my.secrets.getPath cfg.mail.secretName cfg.mail.configFile;
        # HOME, so this is ~/.config/himalaya — where himalaya looks without
        # being told. The old path was ${stateDir}/home/.config because HOME
        # used to be the CONTAINER's home, one level below stateDir.
        mailDir = "${stateDir}/.config/himalaya";
      in {
        # Himalaya has no daemon: it reads config.toml on every invocation,
        # so rotation only re-installs the file — no hermes-agent restart.
        # Same install-then-watch shape as install-agent-authorized-key: the
        # service runs once at activation (secret lands during activation,
        # before inotify watches exist), the path unit covers rotations.
        # No RemainAfterExit: a path unit's `start` on an active oneshot is
        # a no-op, so the re-install would run exactly once and miss rotations.
        systemd.paths.hermes-mail-rotation = {
          description = "Re-install the agent's himalaya config when hermes-mail rotates";
          wantedBy = ["multi-user.target"];
          pathConfig = {
            PathModified = [mailSrc];
            Unit = "hermes-install-mail.service";
            TriggerLimitIntervalSec = "30s";
            TriggerLimitBurst = 10;
          };
        };
        systemd.services.hermes-install-mail = {
          description = "Install the agent's himalaya config";
          wantedBy = ["multi-user.target"];
          before = ["hermes-agent.service"];
          after = ["local-fs.target"];
          serviceConfig = {
            Type = "oneshot";
            Restart = "on-failure";
            RestartSec = 1;
          };
          script = ''
            set -euo pipefail
            if [ ! -s "${mailSrc}" ]; then
              echo "hermes-install-mail: source secret ${mailSrc} missing or empty" >&2
              exit 1
            fi
            # No binary plumbing: himalaya itself arrives through
            # services.hermes-agent.extraPackages, which puts it on the
            # gateway's PATH and in the user's profile. This job installs the
            # config file and nothing else.
            # Own the whole chain, not just the leaf: install -d only fixes
            # ownership on directories it creates, so a ~/.config first made by
            # a root-run installer stays root-owned and the agent can then write
            # nothing under it (this is exactly how a headless HM activation
            # died in dconfSettings on first deploy). The user's config dir
            # must belong to the user.
            install -d -m 0755 -o ${agentUser} -g ${agentUser} ${stateDir}/.config
            install -d -m 0700 -o ${agentUser} -g ${agentUser} ${mailDir}
            install -m 0400 -o ${agentUser} -g ${agentUser} ${mailSrc} ${mailDir}/config.toml
            echo "hermes-install-mail: ${mailDir}/config.toml"
          '';
        };
      }))

      # wake-charon needs no plumbing at all in native mode. It used to be a
      # container-bin symlink plus a :ro mount, because the container's only
      # host inputs were /nix/store and ${stateDir} and a systemPackages entry
      # was invisible in there. The gateway is now an ordinary process on the
      # host, so the script arrives through services.hermes-agent.extraPackages
      # -- which upstream also mirrors into users.users.<user>.packages, so it
      # is on the agent's interactive PATH too, not just the gateway's.

      # No herdr client for the agent container any more. It used to need only a
      # stable binary path, because the socket came for free: herdr ran as
      # `hermes`, whose stateDir is bind-mounted at /data, so the socket was
      # /data/.config/herdr/herdr.sock with no wiring at all. That stopped being
      # true in roadmap Phase C — herdr is now a Home Manager user unit owned by
      # `agent`, so its socket lives in a 0700 home the `hermes` container user
      # cannot traverse. Bridging it would mean an ACL plus a new bind mount for
      # a container that roadmap Phase D removes outright (the gateway runs
      # natively as `agent`, and reaches the socket directly). So the block is
      # gone rather than re-plumbed.
      #
      # CONSEQUENCE, deliberately accepted and not hidden: until Phase D lands,
      # the containerised gateway has no herdr client. Do not deploy Phase C on
      # its own — C and D belong in one deploy.

      # Container mode shares the host network namespace, so every port the
      # gateway opens is a port on makemake. Restrict the known one to io.
      {
        networking.firewall = {
          extraInputRules =
            lib.mkAfter
            (config._module.args.mkRestrictedPortRules {
              port = cfg.firewallPort;
              allowedSources = cfg.firewallAllowedSources;
            }).nft;
          extraCommands = lib.mkIf (!config.networking.nftables.enable) (lib.mkAfter
            (config._module.args.mkRestrictedPortRules {
              port = cfg.firewallPort;
              allowedSources = cfg.firewallAllowedSources;
            }).iptables);
        };
      }
    ]);
  };
}
