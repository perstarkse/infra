{
  lib,
  modules,
  config,
  pkgs,
  ...
}: {
  imports = with modules.nixosModules; [
    options
    shared
    disko
    interception-tools
    system-stylix
    hyprland
    home-module
  ];

  home-manager.users.p = {
    imports = with modules.homeModules; [
      hyprland
      helix
      rbw
      rofi
    ];
    my.programs = {
      rbw = {
        pinentrySource = "tty";
      };
      rofi = {
        withRbw = true;
      };
      helix = {
        enable = true;
        languages = ["nix" "markdown"];
      };
    };
    home.stateVersion = "25.11";
  };

  systemSettings.mainUser.name = "p";

  disko.devices.disk.main.device = "/dev/disk/by-id/ata-QEMU_HARDDISK_QM00001";
  users.users.root.openssh.authorizedKeys.keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII6uq8nXD+QBMhXqRNywwCa/dl2VVvG/2nvkw9HEPFzn p@charon"];
  clan.core.networking.zerotier.controller.enable = true;

  environment.systemPackages = [
    pkgs.wget
  ];
}
