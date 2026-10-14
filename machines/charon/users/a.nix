{ctx, ...}: let
  secondUser = "a";
in {
  # The account, its groups and its password come from the `user-a`
  # clan users service instance (flake/parts/clan.nix). Only the uid is set
  # here, so the account is a fixed 1001 like the main account's 1000.
  users.users.${secondUser}.uid = 1001;

  # Second account: GNOME on the same seat. The list is deliberately short —
  # the modules the main account needs for a tiled, terminal-driven desktop
  # (niri config, noctalia, rofi, qutebrowser, local-ai, agent tooling) either do
  # nothing in a GNOME session or fight it. Not importing the niri home module
  # is also what keeps its niri config and the 4s niri IPC wait out of her
  # activation, since that module gates on the system-wide my.gui.session
  # rather than anything per user. No `sops`/`mail-clients` either: those carry
  # an age keyFile at /home/<user>/.config/sops/age/keys.txt and she has no
  # fleet secrets to decrypt.
  home-manager.users.${secondUser} = {lib, ...}: {
    imports = with ctx.flake.homeModules; [
      fish
      starship
      kitty
      xdg-userdirs
      xdg-mimeapps
      firefox
      chromium
      mail
      bitwarden-client
      ssh
    ];

    my = {
      programs.mail = {
        enable = true;
        clients = ["thunderbird"];
      };
      bitwarden-client.enable = true;
      chromium.enable = true;
      firefox.enable = true;
      fish.enable = true;
      starship.enable = true;
      ssh.enable = true;
      xdg-mimeapps.enable = true;
      xdg-userdirs.enable = true;
    };

    # The main account's lock is a Noctalia keybinding, not an idle trigger.
    # GNOME's automatic-lock defaults have moved between releases, so both keys
    # are set rather than inherited: without this her session stays unlocked
    # whenever she steps away from a seat the other account is using.
    # idle-delay stays at the schema default (300s) and lock-delay at 0.
    # Swedish session: GNOME input source plus LANG. System glibc already
    # ships sv_SE (in supportedLocales via the shared en_US/sv_SE extras),
    # so only the session default changes; the main account keeps en_US.
    home.language.base = "sv_SE.UTF-8";

    # Daily user-flatpak updates: Flathub ships its own CVE fixes outside
    # the NixOS rebuild cycle, so this must not wait for a deploy.
    systemd.user.services.flatpak-user-update = {
      Unit.Description = "Update user Flatpaks";
      Service = {
        Type = "oneshot";
        ExecStart = "/run/current-system/sw/bin/flatpak update --noninteractive --assumeyes";
      };
    };
    systemd.user.timers.flatpak-user-update = {
      Unit.Description = "Daily user Flatpak updates";
      Timer = {
        OnCalendar = "daily";
        Persistent = true;
      };
      Install.WantedBy = ["timers.target"];
    };

    dconf.settings = {
      "org/gnome/desktop/input-sources" = {
        sources = [(lib.hm.gvariant.mkTuple ["xkb" "se"])];
      };
      "org/gnome/desktop/screensaver" = {
        idle-activation-enabled = true;
        lock-enabled = true;
      };
    };
  };
}
