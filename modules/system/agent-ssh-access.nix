# Fleet-wide, non-sudo SSH access for the personal agent.
#
# The agent authenticates as `agent` on every machine in the fleet. `agent` is
# deliberately unprivileged: not in wheel, not in docker, not in libvirtd. The
# only extra group is systemd-journal, so it can read service logs for
# introspection. Escalation is off the table by construction rather than by
# policy: `agent` holds no sudo rule anywhere, and
# security.sudo.wheelNeedsPassword stays true fleet-wide.
#
# Two structural properties matter more than the key options below, and both
# exist because a first cut got them wrong:
#
#  1. The authorized_keys file is ROOT-OWNED and lives in
#     /etc/ssh/authorized_keys.d/, not in the agent's home. An agent that owns
#     its own authorized_keys can `sed -i 's/^restrict //'` and re-enable port
#     forwarding on the next login, which would let it tunnel into every
#     loopback-only daemon on the box.
#
#  2. The agent's HOME is root-owned and NOT writable. sshd reads
#     ~/.ssh/authorized_keys in addition to /etc/ssh/authorized_keys.d/%u, and
#     services.openssh.authorizedKeysInHomedir is a global option with no
#     per-user override — so the only way to stop the agent authorizing itself
#     is to make sure it cannot create that file. Writable scratch space lives
#     in `workDir` instead.
#
# Why the key is installed at activation rather than through nixpkgs'
# `authorizedKeys`: the public half comes from a Clan var, which only exists at
# deploy time. my.secrets.getValue would read it at eval, but that makes
# evaluation fail on a fresh clone until someone has run `clan vars generate`,
# which is a worse trade than a 15-line oneshot.
#
# Note on blast radius: `agent-ssh-key` deploys BOTH halves to every machine
# carrying the tag, because Clan targets whole generators. On the machines that
# do not run the agent, private_key lands in /run/secrets as root-owned 0400
# with no ACL reader granted — so it is readable only by root on those hosts, not
# by any local user. The only reader anywhere is the hermes user on makemake.
#
# Tier A (this module): sshd option restrictions in the key line. Shell, git and
# arbitrary non-sudo commands are allowed; forwarding, ~/.ssh/rc and PTY
# allocation are refused.
#
# Tier B (not implemented): a forced command per host wrapping an allowlist of
# read-only operations. Add it when the real usage pattern is known well enough
# to write that allowlist down.
_: {
  config.flake.nixosModules.agent-ssh-access = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.agent-ssh-access;
    inherit (cfg) home;
    publicKeyPath = config.my.secrets.getPath "agent-ssh-key" "public_key";
  in {
    options.my.agent-ssh-access = {
      enable = lib.mkEnableOption "non-sudo SSH access for the personal agent";

      user = lib.mkOption {
        type = lib.types.str;
        default = "agent";
        description = "Unprivileged account the agent authenticates as.";
      };

      home = lib.mkOption {
        type = lib.types.path;
        default = "/var/empty/agent";
        description = ''
          Account home. Deliberately a path that is never created: sshd reads
          ~/.ssh/authorized_keys in addition to
          /etc/ssh/authorized_keys.d/%u, and services.openssh.authorizedKeysInHomedir
          is a global option with no per-user override — so the only way to stop
          the agent authorizing itself is to ensure no such file can exist.

          /var/empty is root-owned 0555 on NixOS, so even if something creates
          the path, the agent cannot write into it. Writable scratch lives in
          `workDir` instead.
        '';
      };

      workDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/agent-work";
        description = "Writable scratch directory for the agent (clones, scratch files).";
      };

      authorizedKeysFile = lib.mkOption {
        type = lib.types.path;
        default = "/etc/ssh/authorized_keys.d/agent";
        description = ''
          Where the restricted key line is installed. Must live under
          /etc/ssh/authorized_keys.d/ (in sshd's default AuthorizedKeysFile
          list) and stay root-owned: the agent must not be able to rewrite the
          file that constrains it.
        '';
      };

      authorizedKeysOptions = lib.mkOption {
        type = lib.types.str;
        default = "restrict";
        description = ''
          sshd authorized_keys option list prefixed to the agent key line.
          `restrict` denies port/agent/X11 forwarding, PTY allocation and
          ~/.ssh/rc execution, and denies everything else by default. Relax it
          by listing options after `restrict` to re-enable them (e.g.
          `"restrict,pty"` when the agent needs a tty — neither `git clone` nor
          Hermes' `ssh -o BatchMode=yes` backend allocates one).
        '';
      };

      traversePaths = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [];
        description = ''
          Paths the agent may traverse but not list (setfacl u:agent:--x). Use
          for parent directories of anything in `readablePaths` — e.g. /home/p
          when the agent needs to reach /home/p/repos.
        '';
      };

      readablePaths = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [];
        description = "Paths the agent may read and list (setfacl u:agent:r-x).";
      };
    };

    config = lib.mkIf cfg.enable {
      # mutableUsers = false fleet-wide: the group must be declared, or the
      # user's `group = "agent"` has nothing to resolve to.
      users.groups.${cfg.user} = {};

      users.users.${cfg.user} = {
        isNormalUser = true;
        group = cfg.user;
        inherit (cfg) home;
        # No home directory is created or chowned: see the note on `home`. The
        # NixOS users-groups activation chowns homes it manages, so a "make the
        # home root-owned" oneshot loses to activation on every switch.
        createHome = false;
        # Non-interactive, and a shell that sources nothing: an agent that logs
        # in gets a bare prompt, not a login environment it can shape.
        shell = pkgs.bash;
        # Read-only log access. wheel, docker and libvirtd are all
        # root-equivalent and stay out on purpose.
        extraGroups = ["systemd-journal"];
        # Key-only account: no password, no password hash.
        password = "*";
      };

      # Writable scratch space. Created by an idempotent oneshot rather than a
      # tmpfiles rule because tmpfiles only runs at boot, so a directory created
      # by a deploy would not appear until the next reboot.
      systemd.services.agent-workdir = {
        description = "Create ${cfg.user}'s writable scratch directory";
        wantedBy = ["multi-user.target"];
        after = ["local-fs.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          set -euo pipefail
          install -d -m 0700 -o ${cfg.user} -g ${cfg.user} ${cfg.workDir}
        '';
      };

      # Path unit: install the key when Clan deploys or rotates it.
      #
      # Edge-triggered watches alone miss the initial state: secrets land
      # during activation, BEFORE the path unit starts, so on a first deploy
      # the installer never fired and the key sat uninstalled until the next
      # change. PathExists is level-triggered and fires at unit start when
      # the file is already there. The generator directory itself is
      # deliberately NOT watched: the whole /run/secrets tree is one tmpfs
      # that Clan re-mounts via bind --beneath on every deploy, so a
      # directory watch fires once per sibling file and trips the trigger
      # limit (burst 10/30s) into trigger-limit-hit. Three watches on the
      # file look redundant but are not: at unit start after a re-mount,
      # all three fire at once, and if the mtime/ctime/inode then stays
      # identical there is nothing new to react to — the key content is
      # already installed by activation-time ordering (see the service).
      systemd.paths.install-agent-authorized-key = {
        wantedBy = ["multi-user.target"];
        pathConfig = {
          PathExists = publicKeyPath;
          PathChanged = publicKeyPath;
          PathModified = publicKeyPath;
          TriggerLimitIntervalSec = "5s";
          TriggerLimitBurst = 50;
        };
      };

      systemd.services.install-agent-authorized-key = {
        description = "Install the restricted agent SSH public key for ${cfg.user}";
        after = ["local-fs.target"];
        # Belt and suspenders next to the path unit: run at every switch so
        # the key is installed even if the watcher ever trips its limit.
        # The script is idempotent (install -m 0444 of identical content is
        # a no-op write), so running it unconditionally costs one process
        # spawn per deploy, not a key rewrite.
        wantedBy = ["multi-user.target"];
        unitConfig = {
          StartLimitIntervalSec = 300;
          StartLimitBurst = 60;
        };
        serviceConfig = {
          Type = "oneshot";
          # No RemainAfterExit: a path unit activates the service with
          # `systemctl start`, and an already-active oneshot makes that a no-op.
          # With RemainAfterExit the installer ran exactly once (before the key
          # existed) and then ignored every subsequent trigger.
        };
        script = ''
          set -euo pipefail
          if [ ! -s "${publicKeyPath}" ]; then
            # Not an error: a fresh boot before the first deploy has no key yet,
            # and failing here would leave the system degraded. The path unit
            # re-runs this the moment the secret lands.
            echo "agent public key not present yet at ${publicKeyPath}; nothing to install" >&2
            exit 0
          fi
          install -d -m 0755 "$(dirname ${cfg.authorizedKeysFile})"
          key="${cfg.authorizedKeysOptions} $(tr -d '\n' < "${publicKeyPath}" | sed 's/[[:space:]]*$//')"
          # root:root 0444. The agent can read its own restrictions and cannot
          # rewrite them.
          printf '%s\n' "$key" | install -m 0444 -o root -g root /dev/stdin ${cfg.authorizedKeysFile}
        '';
      };

      # Optional filesystem reach for read-only work (e.g. the owner's git
      # checkouts). Idempotent setfacl, not chmod: /home/p is the user's and
      # must not have its mode changed out from under them.
      systemd.services.agent-path-acl = {
        description = "Grant ${cfg.user} traverse/read ACLs for agent workspace paths";
        wantedBy = ["multi-user.target"];
        after = ["local-fs.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = let
          setfacl = lib.getExe' pkgs.acl "setfacl";
          mkLoop = perm: paths: ''
            for path in ${lib.escapeShellArgs paths}; do
              if [ -d "$path" ]; then
                ${setfacl} -m u:${cfg.user}:${perm} "$path"
              else
                echo "agent-path-acl: $path does not exist, skipping" >&2
              fi
            done
          '';
        in ''
          set -euo pipefail
          if ! id -u ${cfg.user} >/dev/null 2>&1; then
            # setfacl resolves the name to a uid; a missing account would fail
            # the unit and leave the system degraded.
            echo "agent-path-acl: user ${cfg.user} does not exist, skipping ACLs" >&2
            exit 0
          fi
          ${mkLoop "--x" cfg.traversePaths}
          ${mkLoop "r-x" cfg.readablePaths}
        '';
      };
    };
  };
}
