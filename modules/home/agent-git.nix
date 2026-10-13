{
  config.flake.homeModules.agentGit = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.agentGit;
  in {
    # Enabled only in an AGENT home block: the authorship exports would
    # mis-attribute p's commits, and the signing key path assumes the
    # agent-git clan vars deploy into agent's ~/.ssh. The /etc/ssh
    # allowed_signers half lives in the machine config (home modules cannot
    # write /etc).
    options.my.agentGit.enable = lib.mkEnableOption "agent git signing, authorship and GitHub push config";

    config = lib.mkIf cfg.enable {
      # user.signingkey points at the PRIVATE key file: exposeUserSecrets
      # deploys no .pub here, and git stats the path before every sign (a
      # missing file aborts the commit).
      # Verified end-to-end on charon 2026-10-12: Good "git" signature for
      # agent@stark.pub via the allowed_signers principal lines.
      programs.git.settings = {
        commit.gpgsign = true;
        gpg.format = "ssh";
        user.signingkey = "/home/agent/.ssh/git_sign_ed25519";
        gpg.ssh.allowedSignersFile = "/etc/ssh/allowed_signers";
        # Shared-tree worker (C4/C5): the agent's workspace is by design
        # repos owned by p (verified 2026-10-12: every git command in
        # /mnt/sdb/repos checkouts dies with "dubious ownership" otherwise).
        # The ownership check protects a user from OTHERS' repos; here the
        # account's purpose is operating the shared tree, so exactly that tree
        # is trusted — not "*", which would silence the check for any
        # foreign-owned repo the agent ever touches (e.g. a copy of someone
        # else's checkout). safe.directory supports no prefix globs — exact
        # paths or a lone "*" — but git compares every leading directory of
        # the repo path, so the top-level entry covers all checkouts under it;
        # ~/projects (a symlink to /mnt/sdb/repos) canonicalizes to the same
        # path. Machines without the shared tree (makemake) carry an inert
        # entry: its agent owns its own checkouts in ~/projects.
        safe.directory = ["/mnt/sdb/repos"];
      };

      # GIT_AUTHOR_* must reach every path agent commits from. ONE logical
      # setting delivered through THREE channels — keep them in sync:
      #   - home.sessionVariables: interactive shells
      #   - herdr's Service.Environment: herdr panes inherit the SERVER's env,
      #     not environment.d (modules/home/herdr.nix notes plugins use the
      #     same lever)
      #   - ~/.bashrc: bash invoked by sshd sources it even non-interactively
      #     (SSH_CLIENT set) — the one path the two mechanisms above don't
      #     reach; verified on charon 2026-10-12 that an ssh-command commit
      #     authored as p without it. HM files are store symlinks, so the
      #     agent cannot edit its own authorship.
      # Removing "the redundant" one of the three silently re-attributes
      # commits from whichever channel you dropped.
      home.sessionVariables = {
        GIT_AUTHOR_NAME = "agent";
        GIT_AUTHOR_EMAIL = "agent@stark.pub";
      };
      systemd.user.services.herdr.Service.Environment = [
        "GIT_AUTHOR_NAME=agent"
        "GIT_AUTHOR_EMAIL=agent@stark.pub"
      ];
      # Enable HM's bash management so integrations land in ~/.bashrc: with
      # programs.bash disabled, direnv's bash hook (and zoxide's) never reach
      # the agent's interactive shells — the checkout dev shells only load
      # via the hook (verified live 2026-10-13: `clan` missing in an agent
      # pane despite the direnv allow being present). The exports ride
      # initExtra; bash sources .bashrc when invoked by sshd too, so the
      # ssh-command authorship path stays covered.
      programs.bash.enable = true;
      programs.bash.initExtra = ''
        export GIT_AUTHOR_NAME=agent
        export GIT_AUTHOR_EMAIL=agent@stark.pub
      '';

      # GitHub pushes go through the agent-git-auth key only (decision C2).
      # IdentitiesOnly yes keeps the fleet mesh key (~/.ssh/id_ed25519) from
      # ever being offered to github.com. github.com's host key is pinned
      # fleet-wide in modules/system/shared.nix, so BatchMode-style
      # non-interactive pushes verify the host without TOFU.
      home.file.".ssh/conf.d/github" = {
        text = ''
          Host github.com
            User git
            IdentityFile ~/.ssh/git_auth_ed25519
            IdentitiesOnly yes
        '';
      };
    };
  };
}
