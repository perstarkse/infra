{
  ctx,
  config,
  pkgs,
  lib,
  ...
}: let
  agentUser = config.my.agent-ssh-access.user;
in {
  # Non-sudo fleet SSH for the personal agent. Unprivileged `agent` account,
  # `restrict`ed key, no wheel/docker/libvirtd, logs only.
  #
  # Shared-space topology: /home/p is p-private (700, ZERO
  # agent ACLs — the old traverse-only grant leaked world-readable dotfiles
  # to any known path; revoked by revoke-agent-legacy-access below). The
  # agent reaches the shared tree via /mnt/sdb/repos directly or its own
  # ~/projects symlink, never by traversing /home/p. writablePaths grants
  # rwX for agent AND p (files either creates must stay writable by the
  # other); the old herdr socket grant is gone — cross-driving p's server
  # goes over explicit `herdr --machine`, never ambient socket rw.
  my.agent-ssh-access = {
    enable = true;
    # Real home, not /var/empty: makemake's agent SSHes in as `agent`
    # (herdr mesh, Phase E), and with no home every remote command starts
    # with "Could not chdir to home directory" noise. Same closure as
    # makemake's: the module's per-user AuthorizedKeysFile Match block
    # ignores a self-written ~/.ssh/authorized_keys regardless.
    home = "/home/agent";
    createHome = true;
    # C5: the shared project tree. Single-level ACLs land at activation;
    # the agent-path-acl-repair timer walks pre-existing content
    # (8.7M inodes — deliberately never in the activation path).
    writablePaths = ["/mnt/sdb/repos"];

    gitSigning.enable = true;
  };

  # p-private home: agent's home becomes 750 + u:p:r-X so p reads everything downhill
  # (NixOS re-applies homeMode on every activation — verified in
  # update-users-groups.pl:238 — so the mode itself needs no oneshot).
  users.users.${agentUser}.homeMode = "750";

  # p's downhill read on agent's home. Recursive + default: a
  # top-level-only grant stops at the first 0700 subdir agent creates.
  # 46k inodes — safe in the activation path (seconds). p-readable-by-design:
  # agent holds nothing p must not see; the boundary is /home/p, not this.
  systemd.services.grant-p-agent-home-read = {
    description = "Grant p downhill r-X on ${agentUser}'s home";
    after = ["local-fs.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "10min";
    };
    script = let
      setfacl = lib.getExe' pkgs.acl "setfacl";
    in ''
      set -euo pipefail
      if [ -d "/home/${agentUser}" ]; then
        ${setfacl} -R -m u:p:r-X /home/${agentUser}
        ${setfacl} -R -d -m u:p:r-X /home/${agentUser}
        # Scrub the grant inside ~/.ssh: ssh-keygen REFUSES a private key
        # whose mode shows group readability — the u:p entry sets the mask
        # to r-x and the mode to 0440 ("UNPROTECTED PRIVATE KEY FILE",
        # verified live on charon 2026-10-12: agent commit signing died on
        # it). p has no need to read agent's keys: p already holds the
        # fleet key. The scrub runs after every grant so the re-applied
        # recursion can never leave the keys broken across deploys.
        ${setfacl} -R -b /home/${agentUser}/.ssh 2>/dev/null || true
      fi
    '';
  };

  # Strip the legacy agent grants on /home/p — traverse on the home
  # and .config chain, rw on p's herdr socket. Idempotent every switch: the
  # config change alone would leave the on-disk ACLs in place forever.
  # No chmod: /home/p's 710 was the ACL mask artifact; removing the entry
  # recomputes the mask, and update-users-groups.pl re-applies homeMode 700
  # every activation anyway. The socket grant never returns: herdr recreates
  # the socket without ACLs and agent-path-acl no longer grants it.
  systemd.services.revoke-agent-legacy-access = {
    description = "Revoke agent ACLs on /home/p (p-private home)";
    after = ["local-fs.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
    };
    script = let
      setfacl = lib.getExe' pkgs.acl "setfacl";
    in ''
      set -euo pipefail
      for path in /home/p /home/p/.config /home/p/.config/herdr /home/p/.config/herdr/herdr.sock; do
        ${setfacl} -x u:agent "$path" 2>/dev/null || true
      done
    '';
  };

  # PATH for `agent` SSH sessions: sshd's default PATH has no
  # /run/current-system/sw. The herdr socket needs no SetEnv: `agent`
  # resolves its own server's socket by default.
  services.openssh.extraConfig = lib.mkAfter ''
    Match User ${agentUser}
        SetEnv PATH=/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin
  '';

  # pi-agent-browser-native probes the managed-session policy lock owner's
  # process start time via ps at the hardcoded paths /bin/ps then /usr/bin/ps
  # (dist/extensions/agent-browser/lib/process-identity.js). NixOS has neither
  # directory, so pi's agent_browser tool fails with "Managed-session policy
  # coordination is unavailable or busy". Symlink /bin/ps onto procps so the
  # deterministic lock path works without relying on PATH.
  system.activationScripts.agent-browser-ps = ''
    mkdir -p /bin
    ln -sfn ${pkgs.procps}/bin/ps /bin/ps
  '';

  # Agent's own space on charon: common toolchain via shared agentProfile.
  home-manager.users.${agentUser} = {
    imports = with ctx.flake.homeModules; [
      agentProfile
    ];

    my.agentProfile = {
      enable = true;
      projectsSymlink = "/mnt/sdb/repos";
    };

    my.herdr.sleepInhibit.enable = true;
  };
}
