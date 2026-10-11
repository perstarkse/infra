# herdr as a NixOS system service, for machines with no Home Manager user.
#
# charon runs herdr from modules/home/herdr.nix as a user unit. makemake has
# `mainUser.enable = false` and no `p` account at all, so that module cannot
# apply there; this is the same service expressed at system scope.
#
# The server runs as the `hermes` user on purpose. herdr keeps its config and
# sockets under $HOME/.config/herdr (src/config/io.rs, config_dir()), and
# /var/lib/hermes is the hermes stateDir — which is ALREADY bind-mounted into
# the agent container as /data. So the socket is reachable from inside the
# container at /data/.config/herdr/herdr.sock with no new volume, no ssh hop and
# no socket ACL, and panes are spawned as the same account the hermes gateway
# already runs as. Verified on the machine: a unix socket bound under
# /var/lib/hermes is connectable from inside hermes-agent via /data.
#
# Sourced from upstream herdrdev/herdr @ bce28752 (herdr 0.9.3), same facts the
# charon module records: `herdr server` is the long-running process (no
# subcommand, no self-daemonise), a second server on a live socket exits 1 so
# Restart=always is safe, and herdr chmods both sockets 0600 with no knob.
{inputs, ...}: {
  config.flake.nixosModules.herdr = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.herdr;
    herdrPkg = cfg.package;
    herdrBin = lib.getExe herdrPkg;
    socketDir = "${cfg.stateDir}/.config/herdr";
    apiSocket = "${socketDir}/herdr.sock";
    clientSocket = "${socketDir}/herdr-client.sock";
    inherit ((import ../../flake/lib/herdr-sockets.nix {inherit pkgs;})) shareScript;
  in {
    options.my.herdr = {
      enable = lib.mkEnableOption "herdr server as a system service (no Home Manager user)";

      package = lib.mkOption {
        type = lib.types.package;
        default = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
        defaultText = "the pinned herdr flake input";
        description = "The herdr package to run.";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "hermes";
        defaultText = "the hermes service account";
        description = ''
          Account the server runs as. Panes are spawned by the server, so this
          is also the identity any agent it starts runs as. It defaults to
          `hermes` because that account's stateDir is the one already visible to
          the agent container.
        '';
      };

      stateDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/hermes";
        defaultText = "/var/lib/hermes (the hermes stateDir)";
        description = ''
          Parent of $HOME. herdr derives its config dir from $HOME, not from
          XDG_CONFIG_HOME, so the server's Environment must set HOME to this.
        '';
      };

      shareWith = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["agent"];
        description = ''
          Local users granted read/write on the herdr sockets, so they can drive
          the server as a client without owning it. Needed when another machine
          reaches this one over SSH as one of these users: herdr chmods the
          sockets 0600 and exposes no knob for it, so the ACL is applied after
          the bind (see flake/lib/herdr-sockets.nix).
        '';
      };

      sshConfig = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = ''
          Contents of the herdr user's ~/.ssh/config. `herdr machine add`
          shells out to plain ssh, so an ssh identity has to be described here
          rather than on the herdr command line. Applied by a oneshot, not
          tmpfiles: tmpfiles only runs at boot, so a rule left the file stale
          for every deploy that was not a reboot.
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      # The binary is also needed on the machine's system PATH: a non-login
      # `ssh agent@… 'herdr …'` gets sshd's default PATH, not any profile, and
      # that is exactly how one machine's herdr reaches another's over the
      # mesh.
      environment.systemPackages = [herdrPkg];

      systemd.services.herdr = {
        description = "herdr coding-agent server (system scope)";
        wantedBy = ["multi-user.target"];
        after = ["network.target"];
        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          # herdr resolves config_dir() from $HOME; without this a system unit
          # would inherit root's or an empty HOME and write its sockets to the
          # wrong place (or nowhere).
          Environment = [
            "HOME=${cfg.stateDir}"
          ];
          ExecStart = "${herdrBin} server";
          Restart = "always";
          RestartSec = 5;
          # `hermes` owns this unit's filesystem trust boundary, not a sandbox.
          # Deliberately no CapabilityBoundingSet/NoNewPrivileges/ProtectHome:
          # this server spawns panes that run coding agents against real
          # checkouts, and that hardening could not be exercised here. The
          # trust boundary is the 0600 socket (chmod'd by herdr, owned by
          # `hermes`) plus the stateDir's 0770. Add sandboxing deliberately,
          # with an agent run to prove it still works.
          # Type=simple means systemd considers the unit started before the
          # socket exists, so any ACL has to be applied after waiting for it.
          # listOf str, so the joined command has to be wrapped, not just
          # concatenated.
          # lib.escapeShellArgs returns a STRING here, not a list, so map
          # escapeShellArg over the combined list rather than `++`-ing one.
          ExecStartPost = lib.optionals (cfg.shareWith != []) [
            (lib.concatStringsSep " " (
              map lib.escapeShellArg (
                [shareScript apiSocket clientSocket] ++ cfg.shareWith
              )
            ))
          ];
        };
      };

      # No tmpfiles: it only runs at boot, so a rule here would leave the file
      # stale across every deploy that is not a reboot.
      systemd.services.herdr-ssh-config = lib.mkIf (cfg.sshConfig != "") {
        description = "Install the herdr user's ssh config";
        wantedBy = ["multi-user.target"];
        # after herdr so the config is in place before herdr (or its
        # ExecStartPost) ever shells out to ssh.
        after = ["herdr.service"];
        serviceConfig.Type = "oneshot";
        script = ''
          set -euo pipefail
          install -d -m 0700 -o ${cfg.user} -g ${cfg.user} ${cfg.stateDir}/.ssh
          install -m 0600 -o ${cfg.user} -g ${cfg.user} /dev/stdin \
            ${cfg.stateDir}/.ssh/config <<'HERDR_SSH_CONFIG'
          ${cfg.sshConfig}
          HERDR_SSH_CONFIG
          echo "herdr-ssh-config: installed ${cfg.stateDir}/.ssh/config"
        '';
      };
    };
  };
}
