{
  config,
  pkgs,
  lib,
  ...
}: let
  secondUser = "a";

  # GDM's switch-user entry point, used to hand the box over without ending the
  # running session. gdm-50.1 common/gdm-common.c: gdm_goto_login_session →
  # create_transient_display → this method (daemon/gdm-local-display-factory.xml).
  switchUserToGreeter = pkgs.writeShellApplication {
    name = "switch-user-greeter";
    text = ''
      exec ${lib.getExe' pkgs.glib "gdbus"} call --system \
        --dest org.gnome.DisplayManager \
        --object-path /org/gnome/DisplayManager/LocalDisplayFactory \
        --method org.gnome.DisplayManager.LocalDisplayFactory.CreateTransientDisplay
    '';
  };
in {
  environment.systemPackages = [
    switchUserToGreeter
  ];

  # Flatpak escape hatch for the second account: she gets GNOME Software
  # (the "app store") with Flathub, user-scope installs so no wheel/sudo is
  # needed. The system base stays declarative; her day-to-day apps go here.
  # enabling flatpak also pulls gnome-software via the gnome module.
  services.flatpak.enable = true;

  # Flathub remote, system scope so every account (including non-wheel ones
  # installing --user) resolves it. No declarative option exists upstream,
  # so one idempotent oneshot.
  systemd.services.flatpak-add-flathub = {
    description = "Add Flathub remote (system)";
    wantedBy = ["multi-user.target"];
    wants = ["network-online.target"];
    after = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.flatpak}/bin/flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo";
    };
  };

  # Swedish layout at the greeter too: GDM inherits the system XKB setting,
  # so Swedish characters work in the password field before any session (and
  # its dconf below) loads. The niri session sets its own layout and is
  # unaffected; only the console keymap follows along.
  services.xserver.xkb.layout = "se";

  # GDM replaced greetd here: greetd runs one greeter session at a time, so
  # handing the machine to the second account meant logging out and losing the
  # running session. GDM can start an extra greeter on a spare VT and keep both
  # sessions alive (logind hands the single DRM master to whichever one is on
  # the active VT). Consequence: her GNOME session lives on its own VT and
  # this niri session stays on the first one.
  services.displayManager = {
    gdm.enable = true;
    # Replaces greetd's initial_session autologin.
    autoLogin = {
      enable = true;
      user = config.my.mainUser.name;
    };
  };

  # Second desktop. Its own mkDefault services (GNOME Online Accounts,
  # evolution-data-server, power-profiles-daemon, tracker indexer) are all
  # defaults, so none of them collide with the networkd setup in shared.nix.
  services.desktopManager.gnome.enable = true;

  # CreateTransientDisplay is auth_admin for every caller class
  # (gdm-50.1 data/org.gnome.displaymanager.policy), which would mean a polkit
  # agent plus a password prompt from inside a bare niri session. The main
  # account is admin on its own machine and the action only starts a greeter —
  # the second user still authenticates to log in. `active` keeps it to a
  # session that actually holds the seat.
  security.polkit.enable = true;
  security.polkit.extraConfig = ''
    polkit.addRule(function (action, subject) {
      if (action.id !== "org.gnome.displaymanager.displayfactory.manage-user-displays") {
        return undefined;
      }
      if (subject.local && subject.active && subject.user === "${config.my.mainUser.name}") {
        return "yes";
      }
      return undefined;
    });
  '';

  # One greeter session name, per-user desktop behind it: GDM's
  # defaultSession is applied to *every* account (see session-dispatch.nix).
  my.sessionDispatch = {
    enable = true;
    users.${secondUser} = "gnome";
  };
}
