# A single greeter session that picks the desktop per username.
#
# Why this exists: nixpkgs' GDM module implements
# `services.displayManager.defaultSession` by running `set-session` in
# display-manager's preStart, and that script calls
# `user.set_session()` for *every* normal user (nixos/modules/services/x11/
# display-managers/set-session.py). One global session name therefore means
# every account gets the same desktop, and it overrides whatever the greeter
# remembered. Hiding the choice behind one session name keeps the per-user
# mapping in one place.
_: {
  config.flake.nixosModules.session-dispatch = {
    pkgs,
    lib,
    config,
    ...
  }: let
    cfg = config.my.sessionDispatch;

    sessionCommands = {
      niri = "${lib.getExe' config.programs.niri.package "niri-session"}";
      gnome = "${lib.getExe pkgs.gnome-session}";
    };

    # Case arms for the listed users; everyone else falls back to my.gui.session.
    defaultCase = [
      ''export XDG_CURRENT_DESKTOP=${cfg.session}''
      ''export XDG_SESSION_DESKTOP=${cfg.session}''
      ''exec ${sessionCommands.${cfg.session}}''
    ];

    userCases =
      lib.mapAttrsToList (
        user: session: ''
          ${user})
            export XDG_CURRENT_DESKTOP=${session}
            export XDG_SESSION_DESKTOP=${session}
            exec ${sessionCommands.${session}}
            ;;
        ''
      )
      cfg.users;

    dispatchScript = pkgs.writeShellApplication {
      name = "${cfg.name}-session";
      text = ''
        case "$(id -un)" in
        ${lib.concatStringsSep "\n" userCases}
        *)
          ${lib.concatStringsSep "\n" defaultCase}
          ;;
        esac
      '';
    };

    # destination matters: the session aggregation in
    # services/display-managers/default.nix only lndirs
    # $pkg/share/wayland-sessions into sessionData.desktops, and providedSessions
    # is what it validates the name against.
    sessionFile = pkgs.writeTextFile {
      name = "${cfg.name}-session.desktop";
      destination = "/share/wayland-sessions/${cfg.name}.desktop";
      derivationArgs.passthru.providedSessions = [cfg.name];
      text = ''
        [Desktop Entry]
        Name=${cfg.name}
        Comment=Per-user session (default desktop, or as configured per account)
        Exec=${lib.getExe dispatchScript}
        Type=Application
        DesktopNames=${cfg.name}
      '';
    };
  in {
    options.my.sessionDispatch = {
      enable = lib.mkEnableOption "Per-user session dispatch behind one greeter session";

      name = lib.mkOption {
        type = lib.types.str;
        default = "charon";
        description = "Name of the synthetic greeter session. This is the only name set as services.displayManager.defaultSession, because that option is global (see set-session.py).";
      };

      session = lib.mkOption {
        type = lib.types.enum (lib.attrNames sessionCommands);
        default = config.my.gui.session;
        description = "Session for users not listed in {option}`my.sessionDispatch.users`. Defaults to the machine-wide {option}`my.gui.session`, which stays the source of truth for the main account.";
      };

      users = lib.mkOption {
        type = lib.types.attrsOf (lib.types.enum (lib.attrNames sessionCommands));
        default = {};
        example = {
          a = "gnome";
        };
        description = "Username to session mapping. Keep accounts here out of the main account's own configuration so a DE change for one user does not touch the other.";
      };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [dispatchScript];

      services.displayManager.sessionPackages = [sessionFile];

      # mkForce: the niri module sets defaultSession = "niri" at normal
      # priority, and a second normal-priority definition would be a conflict.
      services.displayManager.defaultSession = lib.mkForce cfg.name;
    };
  };
}
