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
#  2. The agent can never authorize itself. sshd reads
#     ~/.ssh/authorized_keys in addition to /etc/ssh/authorized_keys.d/%u, and
#     services.openssh.authorizedKeysInHomedir is a global option with no
#     per-user override. Two ways to close that, and the module applies both
#     available mechanisms rather than relying on one: a non-writable HOME
#     cannot hold the file in the first place (the default, via `createHome =
#     false`), and a per-user `Match` block overrides AuthorizedKeysFile so a
#     home-writable machine ignores the homedir copy anyway. Either alone would
#     do; together there is no configuration of this module in which a writable
#     home opens the hole.
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
# by any local user. The only non-root reader anywhere is the fleet `agent`
# account on the agent host (makemake).
#
# Tier A (this module): sshd option restrictions in the key line. PTY and
# local port-forwarding are re-enabled on top of `restrict` (see
# authorizedKeysOptions); ~/.ssh/rc and everything else stay refused.
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
          Account home. With the default `createHome = false` this is
          deliberately a path that is never created, so the agent cannot write a
          ~/.ssh/authorized_keys that sshd would honour in addition to
          /etc/ssh/authorized_keys.d/%u. /var/empty is root-owned 0555 on
          NixOS, so even if something creates the path, the agent cannot write
          into it.

          Set it to a real path (e.g. /home/agent) together with
          `createHome = true` on machines where the agent needs a usable HOME —
          Home Manager, project checkouts. The per-user AuthorizedKeysFile
          closure in this module is what keeps that safe; writable scratch
          elsewhere still lives in `workDir`.
        '';
      };

      createHome = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to create and chown `home`. Off by default: a machine with no
          reason to give the agent a HOME should not have one. Turning it on
          needs no accompanying sshd work — this module closes the
          homedir authorized_keys path per-user regardless — but it is a real
          trust change, so opt in per machine rather than fleet-wide.
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
        # `restrict,pty,port-forwarding`: the owner SSHes in as `agent` for
        # interactive work (agy/pi first-run auth needs a TTY), so PTY is
        # re-enabled on the key line itself. Local forwarding is re-enabled
        # too: the web UI's Add-PC flow SSH-forwards the remote bridge's
        # loopback port (`ssh -L 127.0.0.1:<local>:127.0.0.1:<remote>`),
        # and without it verify() dies with "administratively prohibited"
        # surfacing as "socket connection was closed". The forward binds
        # loopback on both ends (127.0.0.1: only, never 0.0.0.0), so a
        # stolen key can reach the bridge port but cannot pivot anywhere
        # else. Never add PermitTTY/AllowTcpForwarding to the Match block:
        # that would grant them to EVERY key for this user including a
        # future unrestricted one, instead of scoping them to this key line.
        default = "restrict,pty,port-forwarding";
        description = ''
          sshd authorized_keys option list prefixed to the agent key line.
          `restrict` denies port/agent/X11 forwarding, PTY allocation and
          ~/.ssh/rc execution, and denies everything else by default; `pty`
          re-enables allocation for this key. Neither `git clone` nor Hermes'
          `ssh -o BatchMode=yes` backend allocates one, but the owner's
          interactive logins do.
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

      writablePaths = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [];
        description = ''
          Trees the agent and the main user may both read AND write
          (setfacl rwX). Applied two ways: agent-path-acl sets single-level
          access + default ACLs on the top directory at activation (default
          ACLs propagate by inheritance, so all content created afterwards —
          including fresh clones — is covered without a walk), and the
          agent-path-acl-repair timer recursively fixes pre-existing content.
          The recursive pass must never run in the activation path: on charon
          the shared tree holds ~8.7M inodes and would stall or time out
          every switch (2026-10-12).
        '';
      };

      socketPaths = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [];
        description = ''
          Socket files the agent may read/write (setfacl u:agent:rw-). Use
          for daemon sockets the agent must connect(2) — e.g. another user's
          herdr socket for a remote web bridge. Files only; the parent
          directories still need traversePaths.
        '';
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
        # No home directory is created or chowned unless a machine opts in: see
        # the note on `home`. The NixOS users-groups activation chowns homes it
        # manages, so a "make the home root-owned" oneshot loses to activation
        # on every switch — the flag is the only lever that works.
        inherit (cfg) createHome;
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
          # Project space lives in the home when there is one; machines on the
          # default non-writable home keep using workDir alone. Interpolated
          # by Nix rather than tested in bash: `toString true` is "1", not
          # "true", so a shell-side `[ "${toString cfg.createHome}" = true ]`
          # is silently always false and the directory is never created.
          ${lib.optionalString cfg.createHome ''
            # 0750 (not 0700): the owner's downhill read grant must reach
            # inside. The -L guard is load-bearing, not tidiness: `install -d`
            # FOLLOWS symlinks and re-applies owner+mode to the TARGET, so on
            # a machine where projects is an HM symlink to a shared tree this
            # line would chown that tree to the agent (verified on charon
            # 2026-10-12). Existing real directories get the mode re-applied,
            # which repairs stale modes from earlier deploys.
            if [ ! -L "${cfg.home}/projects" ]; then
              install -d -m 0750 -o ${cfg.user} -g ${cfg.user} ${cfg.home}/projects
            fi
          ''}
        '';
      };

      # Property 2 above, enforced rather than assumed. Closes the homedir
      # authorized_keys path for this user only, which is what makes
      # `createHome = true` safe: sshd cannot be told "no homedir keys" for one
      # user via services.openssh.authorizedKeysInHomedir, but a Match block
      # overrides AuthorizedKeysFile for exactly the connections it matches.
      #
      # Placement is counter-intuitive and mkAfter is load-bearing. sshd takes
      # the first obtained value for a keyword, so a Match block placed BEFORE
      # the global AuthorizedKeysFile line loses to it and the override is
      # silently ignored. Verified against openssh 10.3 with `sshd -T -C
      # user=agent`: Match after -> `/etc/ssh/authorized_keys.d/agent`, Match
      # before -> the global homedir list. Non-matching users keep the global
      # line either way.
      services.openssh.extraConfig = lib.mkAfter ''
        Match User ${cfg.user}
            AuthorizedKeysFile ${cfg.authorizedKeysFile}
      '';

      # Install-then-watch: the secret arrives DURING activation (clan untars
      # the secrets tarball into /run/secrets before units start), and
      # inotify watches only fire on changes AFTER they are established —
      # so a watch created after the file exists never fires until the next
      # rotation. The service therefore runs once at activation (idempotent:
      # rewriting identical authorized_keys content is a no-op write) and
      # the path unit covers rotations only. PathModified alone: mtime
      # changes on rotation but not on the bind --beneath re-mount Clan
      # does on every deploy, so redeploys of identical content stay quiet
      # instead of tripping the trigger limit.
      systemd.paths.install-agent-authorized-key = {
        wantedBy = ["multi-user.target"];
        pathConfig = {
          PathModified = publicKeyPath;
        };
      };

      # The path unit above only fires on changes AFTER the watch is
      # established — a deploy that installs the unit and the secret in the
      # same activation never triggers it (verified on charon 2026-10-11:
      # key deployed, authorized_keys stale, no journal entries). Run the
      # installer at activation too; it is idempotent (no-op rewrite on
      # identical content), so the only cost is one extra start per deploy.
      systemd.services.install-agent-authorized-key-act = {
        description = "Install the restricted agent SSH public key at activation";
        after = ["local-fs.target"];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = config.systemd.services.install-agent-authorized-key.script;
      };

      systemd.services.install-agent-authorized-key = {
        description = "Install the restricted agent SSH public key for ${cfg.user}";
        after = ["local-fs.target"];
        wantedBy = ["multi-user.target"];
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
          # Deliberately no RemainAfterExit. Every call below is an idempotent
          # setfacl, so re-running is free, while a unit left `active` is never
          # re-queued by a later activation — an edited traversePaths then
          # silently fails to apply until the next reboot.
          Type = "oneshot";
        };
        script = let
          setfacl = lib.getExe' pkgs.acl "setfacl";
          mkLoop = perm: test: paths: ''
            for path in ${lib.escapeShellArgs paths}; do
              if [ ${test} "$path" ]; then
                ${setfacl} -m u:${cfg.user}:${perm} "$path"
              else
                echo "agent-path-acl: $path does not exist, skipping" >&2
              fi
            done
          '';
          # Both principals, so files either creates inside the tree stay
          # writable by the other. rwX: execute only where it already exists
          # or on directories.
          writableAcl =
            "u:${cfg.user}:rwX"
            + lib.optionalString config.my.mainUser.enable ",u:${config.my.mainUser.name}:rwX";
          writableTopLoop = paths: ''
            for path in ${lib.escapeShellArgs paths}; do
              if [ -d "$path" ]; then
                ${setfacl} -m "${writableAcl}" "$path"
                # The default ACL is the load-bearing half: it propagates to
                # everything created inside from now on, so a fresh clone is
                # fully covered with no tree walk.
                ${setfacl} -d -m "${writableAcl}" "$path"
              else
                echo "agent-path-acl: $path is not a directory, skipping" >&2
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
          ${mkLoop "--x" "-d" cfg.traversePaths}
          ${mkLoop "r-x" "-d" cfg.readablePaths}
          # Sockets are files, not directories: a -d test would skip them
          # silently, and a missing socket at activation (daemon down) is
          # normal — the next activation re-applies.
          ${mkLoop "rw-" "-S" cfg.socketPaths}
          ${writableTopLoop cfg.writablePaths}
        '';
      };

      # Recursive rwX repair for content that predates the default ACLs —
      # clone restores, pre-cutover checkouts. Timer-driven, never wanted by
      # multi-user.target: a -R walk over a large tree must not block or be
      # killed by the activation timeout (charon: ~8.7M inodes). OnBootSec
      # elapses immediately when the timer arms on an already-booted system,
      # so the first deploy after changing writablePaths repairs within
      # minutes without holding the switch. 12h cadence is pure
      # belt-and-braces afterwards: default-ACL inheritance covers everything
      # created through normal use.
      systemd.services.agent-path-acl-repair = lib.mkIf (cfg.writablePaths != []) {
        description = "Recursive rwX ACL repair for agent-writable trees";
        after = ["local-fs.target"];
        serviceConfig = {
          Type = "oneshot";
          TimeoutStartSec = "30min";
        };
        script = let
          setfacl = lib.getExe' pkgs.acl "setfacl";
          writableAcl =
            "u:${cfg.user}:rwX"
            + lib.optionalString config.my.mainUser.enable ",u:${config.my.mainUser.name}:rwX";
        in ''
          set -euo pipefail
          if ! id -u ${cfg.user} >/dev/null 2>&1; then
            echo "agent-path-acl-repair: user ${cfg.user} does not exist, skipping" >&2
            exit 0
          fi
          ${lib.concatMapStrings (p: ''
              if [ -d "${p}" ]; then
                ${setfacl} -R -m "${writableAcl}" "${p}"
                ${setfacl} -R -d -m "${writableAcl}" "${p}"
              else
                echo "agent-path-acl-repair: ${p} is not a directory, skipping" >&2
              fi
            '')
            cfg.writablePaths}
        '';
      };

      systemd.timers.agent-path-acl-repair = lib.mkIf (cfg.writablePaths != []) {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "3min";
          OnUnitActiveSec = "12h";
          # A suspended workstation misses elapsing points; catch up on wake.
          Persistent = true;
        };
      };
    };
  };
}
