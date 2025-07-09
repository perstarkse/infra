{
  lib,
  modules,
  config,
  pkgs,
  ...
}: {
  imports = [
    modules.nixosModules.options
    modules.nixosModules.shared
    modules.nixosModules.disko
    modules.nixosModules.interception-tools
    modules.nixosModules.system-stylix
    modules.nixosModules.hyprland
    modules.nixosModules.home-module
  ];

  home-manager.users.p = {
    imports = [
      modules.homeModules.hyprland
    ];
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
