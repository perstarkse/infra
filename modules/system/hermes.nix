# Personal agent: Hermes Agent in container mode on makemake.
#
# Upstream ships `nixosModules.default`; this module is the fleet wrapper that
# pins the pieces the generic module deliberately leaves open:
#
#   - container mode on, docker backend (makemake already has
#     virtualisation.docker.enable from my.docker.enable, and upstream's
#     mkDefault for that option collides with a podman backend here)
#   - stateDir on RAID1 xfs under /var/lib. NOT /storage: that is mergerfs over
#     HDDs with dropcacheonclose, and the agent's session DB is SQLite.
#   - every durable agent path (state, workspace, key) inside stateDir, so one
#     restic job covers the lot and nothing important lives on a bind mount
#     outside the backup
#   - the fleet SSH private key copied in by my.secrets.exposeUserSecrets, plus
#     a GitHub known_hosts so `restrict`-ed key auth never prompts
#   - the gateway API port gated to the io router, because container mode runs
#     with --network=host (upstream nixosModules.nix)
#
# Channels only: backend.mode (browser dashboard / Hermes Desktop) is not
# supported in container mode. That is the accepted trade for letting the agent
# apt/pip/npm install into a persistent environment.
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
    sshDir = "${stateDir}/home/.ssh";
    envFile = config.my.secrets.getPath cfg.envSecretName "env";
    sshKeyFile = config.my.secrets.getPath cfg.sshKeySecretName "private_key";
    # Re-render $HERMES_HOME/.env from the secret.
    #
    # Upstream merges `environmentFiles` into .env in a *system activation
    # script* only (nixosModules.nix:455, "each activation writes .env again").
    # The container's preStart does not re-merge, so a secret rotation followed
    # by a plain restart leaves the agent on the previous credentials. This
    # runs before the restart so rotation actually takes effect.
    renderEnvScript = pkgs.writeShellScript "hermes-render-env" ''
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
    '';
    # One restarter for both consumers of the shared secret, so the gateway and
    # the signal-cli daemon can never end up on different account numbers.
    restartUnitsScript = pkgs.writeShellScript "hermes-env-restart-units" ''
      set -euo pipefail
      # try-restart first, then start: a daemon that is *stopped* (e.g. because
      # its secret was missing and it exhausted its start limit) is only brought
      # up by the start fallback.
      for unit in hermes-agent.service signal-cli.service; do
        ${lib.getExe pkgs.systemd}/systemctl try-restart "$unit" \
          || ${lib.getExe pkgs.systemd}/systemctl start "$unit"
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

      model = lib.mkOption {
        type = lib.types.str;
        default = "anthropic/claude-sonnet-4";
        description = "Model id for the default provider.";
      };

      baseUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Provider base URL. null keeps the provider default (OpenRouter).";
      };

      firewallPort = lib.mkOption {
        type = lib.types.port;
        default = 8642;
        description = ''
          Gateway API server port. It binds 127.0.0.1 by default, but container
          mode shares the host network, so the port is gated to the router
          anyway: a later API_SERVER_HOST change must not publish it to the LAN.
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
        services.hermes-agent = {
          inherit (cfg) enable;
          container = {
            inherit (cfg) enable;
            backend = "docker";
            # No extraVolumes: upstream already bind-mounts /nix/store read-only
            # and ${stateDir} → /data (nixosModules.nix:679), and the SSH key and
            # known_hosts are installed under ${stateDir}/home, which upstream
            # mounts as the container's HOME.
          };
          addToSystemPackages = true;

          # Merged into $HERMES_HOME/.env on every activation, so a rotated key
          # needs a gateway restart, not a container rebuild.
          environmentFiles = [envFile];

          settings = {
            model =
              {
                default = cfg.model;
              }
              // lib.optionalAttrs (cfg.baseUrl != null) {base_url = cfg.baseUrl;};
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

        my.secrets.allowReadAccess =
          [
            {
              readers = ["hermes"];
              path = envFile;
            }
          ]
          ++ lib.optional cfg.exposeFleetSshKey {
            readers = ["hermes"];
            path = sshKeyFile;
          };

        # Rotate hermes-env → re-render .env, then restart BOTH consumers (the
        # gateway and the signal-cli daemon, which reads SIGNAL_ACCOUNT from the
        # same file). The upstream module ships no rotation handling at all (no
        # systemd.paths, no restartTriggers) and the units are byte-identical
        # across content rotations, so a restartTriggers list on /run/secrets
        # paths would never fire — same reason ntfy-sh and gatus watch the file.
        #
        # Hand-written rather than spread from mkTryRestartOnRotation because the
        # helper restarts exactly one service and would collide with this
        # module's own `systemd.services` definitions.
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
            ExecStart = "${renderEnvScript} && ${restartUnitsScript}";
          };
        };
      }

      (lib.mkIf cfg.exposeFleetSshKey {
        my.secrets.exposeUserSecrets = [
          {
            enable = true;
            user = "hermes";
            secretName = cfg.sshKeySecretName;
            file = "private_key";
            dest = "${sshDir}/id_ed25519";
            mode = "0400";
          }
        ];

        # Host keys for non-interactive `restrict`ed key auth. This has to land
        # in the agent's own $HOME/.ssh — the container's HOME is
        # ${stateDir}/home, and host /etc is not mounted in, so a file in
        # environment.etc would never be read. Fleet keys collected with
        # ssh-keyscan over the LAN on 2026-09-29; github's is the same key the
        # workstation pins in programs.ssh.knownHosts (modules/system/shared.nix).
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
            install -d -m 0700 -o ${agentUser} -g ${agentUser} ${sshDir}
            install -m 0644 -o ${agentUser} -g ${agentUser} /dev/stdin ${sshDir}/known_hosts <<'KNOWN_HOSTS'
            github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
            charon.lan,10.0.0.15 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINysM9VHtOcjYDAZCTuJl+hjNNHlFExmDx5J7o40Vljh
            10.0.0.1 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMPugZkqgjBKletbzaNipPLSrq5+ToQFBLyCojQLD8pt
            10.0.0.10 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMLhhyxdh0dr+tfcyBgv9K0s5nK9mfwOENBnFVteZOB9
            KNOWN_HOSTS
          '';
        };
      })

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
