{
  config.flake.nixosModules.shared = {
    config,
    clan-core,
    lib,
    pkgs,
    ...
  }: let
    mainUser = config.systemSettings.mainUser.name;
  in {
    imports = [
      clan-core.clanModules.sshd
      clan-core.clanModules.root-password
      clan-core.clanModules.user-password
    ];

    system.stateVersion = "25.11";

    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };

    programs.fish.enable = true;

    environment.systemPackages = with pkgs; [
      pciutils
      vim
      htop
      usbutils
      util-linux
    ];

    i18n.defaultLocale = "en_US.UTF-8";

    i18n.extraLocaleSettings = {
      LC_ADDRESS = "sv_SE.UTF-8";
      LC_IDENTIFICATION = "sv_SE.UTF-8";
      LC_MEASUREMENT = "sv_SE.UTF-8";
      LC_MONETARY = "sv_SE.UTF-8";
      LC_NAME = "sv_SE.UTF-8";
      LC_NUMERIC = "sv_SE.UTF-8";
      LC_PAPER = "sv_SE.UTF-8";
      LC_TELEPHONE = "sv_SE.UTF-8";
      LC_TIME = "sv_SE.UTF-8";
    };

    services.avahi.enable = true;

    clan.user-password.user = mainUser;

    users.users.${mainUser} = {
      isNormalUser = true;
      extraGroups = ["wheel" "networkmanager" "video" "input" "libvirtd" "kvm" "qemu-libvirtd" "docker"];
      uid = 1000;
      shell = pkgs.fish;
      openssh.authorizedKeys.keys =
        # Combine root's keys with the user's extra keys
        config.users.users.root.openssh.authorizedKeys.keys
        ++ config.systemSettings.mainUser.extraSshKeys;
    };
  };
}
