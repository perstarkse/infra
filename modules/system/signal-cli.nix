# signal-cli daemon for the personal agent.
#
# Hermes' Signal adapter does not speak the Signal protocol: it talks to a
# signal-cli HTTP daemon (SSE inbound, JSON-RPC outbound) and needs only the two
# required vars SIGNAL_HTTP_URL and SIGNAL_ACCOUNT. The adapter builds plain
# httpx URLs against that host, so the endpoint has to be TCP — signal-cli's
# --socket option is not usable from Hermes.
#
# Why it runs on the host, not in the agent's container:
#   - container mode runs with --network=host, so the container's loopback IS
#     makemake's loopback. SIGNAL_HTTP_URL=http://127.0.0.1:<port> reaches a
#     host-side daemon with no port publishing and no extra container.
#   - signal-cli is not in apt or snap (upstream ships a GitHub release tarball)
#     and needs a JVM, so putting it in the Ubuntu container image is the
#     awkward path. nixpkgs already packages both.
#
# Security note, stated plainly: signal-cli's HTTP/TCP/socket interfaces have no
# authentication of any kind — `signal-cli daemon --help` offers no key, token
# or header option. Anything in makemake's network namespace can therefore send
# and receive as the linked account. Loopback-only binding keeps it off the LAN;
# the restricted-port rule below keeps it there even if that default ever
# changes. Blast radius is "act as the Signal account", not "steal the Signal
# identity" — the account credentials live in the state directory, not the API.
# It therefore runs as its own unprivileged user, not root.
#
# Rotation of the account secret is handled in modules/system/hermes.nix, which
# owns the shared hermes-env secret: one path unit and one restarter cover both
# this daemon and the agent, so the two can never run on different numbers.
_: {
  config.flake.nixosModules.signal-cli = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.signal-cli;
    stateDir = "/var/lib/signal-cli";
    envFile = config.my.secrets.getPath cfg.accountSecretName cfg.accountSecretFile;
    # The account is not a Nix value: read it from the secret at unit start so
    # the number never enters the flake, the git tree, or the /nix/store.
    startScript = pkgs.writeShellScript "signal-cli-start" ''
      set -euo pipefail
      if [ ! -r "${envFile}" ]; then
        echo "signal-cli: cannot read ${envFile}" >&2
        exit 1
      fi
      account=$(sed -n 's/^SIGNAL_ACCOUNT=//p' "${envFile}" | tail -n 1)
      # Tolerate a quoted value, since the env file is hand-edited via
      # `clan vars set`. Everything else must be strict E.164.
      account=''${account#\"}; account=''${account%\"}
      account=''${account#\'}; account=''${account%\'}
      if ! printf '%s' "$account" | grep -Eq '^\+[1-9][0-9]{6,14}$'; then
        # Deliberately does not echo the value: this journal is shipped to the
        # router.
        echo "signal-cli: SIGNAL_ACCOUNT is missing or not E.164 in ${envFile}" >&2
        exit 1
      fi
      exec ${pkgs.signal-cli}/bin/signal-cli \
        --scrub-log \
        -c ${stateDir} \
        -a "$account" \
        daemon \
        --http 127.0.0.1:${toString cfg.port}
    '';
  in {
    options.my.signal-cli = {
      enable = lib.mkEnableOption "signal-cli daemon for the agent's Signal channel";

      accountSecretName = lib.mkOption {
        type = lib.types.str;
        default = "hermes-env";
        description = ''
          vars generator holding SIGNAL_ACCOUNT for this daemon.

          The number never appears in a Nix expression. It is read from the
          secret at unit start, which also means the agent and the daemon cannot
          disagree: Hermes requires SIGNAL_ACCOUNT in the same env file
          (gateway/platforms/signal.py), so there is exactly one copy.

          Keep this equal to my.hermes.envSecretName — they only diverge if one
          of the two is overridden.
        '';
      };

      accountSecretFile = lib.mkOption {
        type = lib.types.str;
        default = "env";
        description = "File inside accountSecretName's output carrying SIGNAL_ACCOUNT.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 8085;
        description = ''
          HTTP port for the daemon. Hermes reads this as SIGNAL_HTTP_URL.

          Deliberately not 8080: makemake's openwebui container runs with
          --network=host on 8080, and a second bind in the same network
          namespace loses the race at boot.
        '';
      };

      firewallAllowedSources = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["10.0.0.1"];
        description = "Sources allowed to reach the port. The daemon binds loopback anyway.";
      };
    };

    config = lib.mkIf cfg.enable {
      # A dedicated account, so a flaw in an unauthenticated HTTP surface lands
      # on an unprivileged user owning nothing but its own state directory.
      users.groups.signal-cli = {};
      users.users.signal-cli = {
        isSystemUser = true;
        group = "signal-cli";
        description = "signal-cli daemon for the agent's Signal channel";
      };

      # The daemon runs as its own user, so it needs its own ACL reader on the
      # env secret. Without this it cannot read SIGNAL_ACCOUNT: the file is
      # 0400 root:root with setfacl readers, and hermes' entry does not cover
      # the signal-cli user.
      my.secrets.allowReadAccess = [
        {
          readers = ["signal-cli"];
          path = envFile;
        }
      ];

      systemd.services.signal-cli = {
        description = "signal-cli daemon (HTTP) for the agent's Signal channel";
        wantedBy = ["multi-user.target"];
        after = ["network-online.target"];
        serviceConfig =
          {
            Type = "simple";
            User = "signal-cli";
            Group = "signal-cli";
            Environment = "HOME=${stateDir}";
            ExecStart = "${startScript}";
            # A missing or malformed secret is a configuration error, not a
            # transient one. `always` + a 5s delay turned that into a permanent
            # 6-restarts-per-minute loop (137 restarts observed on first
            # deploy). Bounded backoff instead: it retries hard at first, then
            # settles at RestartMaxDelaySec. The hermes-env rotation restarter in
            # modules/system/hermes.nix starts the unit if it is stopped, so a
            # fixed secret brings the daemon up without a manual restart.
            Restart = "always";
            RestartSec = "5s";
            RestartSteps = 5;
            RestartMaxDelaySec = "10min";
          }
          // config._module.args.mkHardenedServiceConfig {
            stateDirectory = "signal-cli";
            stateDirectoryMode = "0700";
            protectSystem = "strict";
            restrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
            umask = "0077";
          }
          // {
            # A JVM JITs its own bytecode and mmaps it W+X, so the fleet-wide
            # MemoryDenyWriteExecute=true would kill the daemon at startup. Every
            # other hardening knob from mkHardenedServiceConfig still applies.
            MemoryDenyWriteExecute = false;
          };
      };

      # The daemon binds loopback by default, so this only matters if that ever
      # changes: keep the Signal account off the LAN, io excepted.
      networking.firewall = {
        extraInputRules =
          lib.mkAfter
          (config._module.args.mkRestrictedPortRules {
            inherit (cfg) port;
            allowedSources = cfg.firewallAllowedSources;
          }).nft;
        extraCommands = lib.mkIf (!config.networking.nftables.enable) (lib.mkAfter
          (config._module.args.mkRestrictedPortRules {
            inherit (cfg) port;
            allowedSources = cfg.firewallAllowedSources;
          }).iptables);
      };
    };
  };
}
