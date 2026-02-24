{inputs, ...}: {
  config.flake.nixosModules.shared = {
    config,
    pkgs,
    ...
  }: let
    mainUser = config.my.mainUser.name;
  in {
    system.stateVersion = "25.11";

    nixpkgs.overlays = [
      (_final: prev: {
        unstable = import inputs."nixpkgs-unstable" {
          inherit (prev.stdenv.hostPlatform) system;
          inherit (config.nixpkgs) config;
        };
      })
    ];

    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };

    programs = {
      fish.enable = true;
      nix-ld.enable = true;
    };

    environment.systemPackages = with pkgs; [
      pciutils
      helix
      htop
      usbutils
      util-linux
      wget
      ranger
      kitty
      ripgrep
      fd
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
    users = {
      mutableUsers = false;
      defaultUserShell = pkgs.fish;

      users.${mainUser} = {
        isNormalUser = true;
        extraGroups = ["wheel" "networkmanager" "video" "input" "libvirtd" "kvm" "qemu-libvirtd"];
        uid = 1000;
        shell = pkgs.fish;
        openssh.authorizedKeys.keys =
          # Combine root's keys with the user's extra keys
          config.users.users.root.openssh.authorizedKeys.keys
          ++ config.my.mainUser.extraSshKeys;
      };
    };

    programs.ssh = {
      startAgent = true;
      knownHosts = {
        github = {
          hostNames = ["github.com"];
          publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
        };
      };
    };

    networking = {
      networkmanager.enable = false;
      enableIPv6 = true;
    };

    nix.settings = {
      trusted-users = ["root" mainUser];
      "download-buffer-size" = 268435456;
    };
  };
}
