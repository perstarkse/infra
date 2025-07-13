{
  modules,
  lib,
  config,
  pkgs,
  ...
}: {
  imports = with modules.nixosModules; [
    home-module
    sound
    options
    shared
    disko
    interception-tools
    system-stylix
    hyprland
    ./secrets.nix
  ];

  home-manager.users.${config.systemSettings.mainUser.name} = {
    imports = with modules.homeModules; [
      options
      hyprland
      helix
      rbw
      rofi
      git
      direnv
      fish
      dunst
      ncspot
      zellij
      starship
      qutebrowser
      looking-glass-client
      bitwarden-client
      blinkstick-scripts
      mail
    ];
    my = {
      secrets = config.systemSettings.sharedSecretPaths;

      programs = {
        mail = {
          clients = ["aerc" "thunderbird"];
        };
        rbw = {
          pinentrySource = "tty";
        };
        rofi = {
          withRbw = true;
        };
        helix = {
          languages = ["nix" "markdown"];
        };
      };
    };

    home.stateVersion = "25.11";
  };

  systemSettings.mainUser.name = "p";

  systemSettings.userSecrets = ["mail-gmail-1-password" "mail-personal-1-password"];

  time.timeZone = "Europe/Stockholm";

  disko.devices.disk.main.device = "/dev/disk/by-id/ata-QEMU_HARDDISK_QM00001";

  users.users.root.openssh.authorizedKeys.keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII6uq8nXD+QBMhXqRNywwCa/dl2VVvG/2nvkw9HEPFzn p@charon"];

  clan.core.networking.zerotier.controller.enable = true;

  environment.systemPackages = [
    # pkgs.wget
  ];
}
