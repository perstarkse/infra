{
  flakeConfig,
  pkgs,
  ...
}: {
  imports = [
    flakeConfig.flake.nixosModules.shared
    flakeConfig.flake.nixosModules.disko
    flakeConfig.flake.nixosModules.interception-tools
    flakeConfig.flake.nixosModules.system-stylix
    flakeConfig.flake.nixosModules.hyprland

    flakeConfig.flake.nixosModules.home-manager
  ];

  home-manager.users.p = {
    imports = [
      flakeConfig.flake.homeModules.hyprland
    ];
  };

  users.users.user.name = "p";
  disko.devices.disk.main.device = "/dev/disk/by-id/ata-QEMU_HARDDISK_QM00001";
  users.users.root.openssh.authorizedKeys.keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII6uq8nXD+QBMhXqRNywwCa/dl2VVvG/2nvkw9HEPFzn p@charon"];
  clan.core.networking.zerotier.controller.enable = true;

  environment.systemPackages = [
    pkgs.wget
  ];
}
