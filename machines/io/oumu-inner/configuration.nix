{ config, pkgs, lib, inputs, ... }:

{
  imports = [
  ];

  # Bootloader
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda";

  # Resize root partition to fill disk on boot
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    autoResize = true;
  };
  
  boot.growPartition = true;

  # Hostname
  networking.hostName = "oumu";

  networking.networkmanager.enable = false;
  networking.useNetworkd = true;
  networking.useDHCP = false;
  
  systemd.network.networks."10-wan" = {
    matchConfig.Name = ["en*" "eth*"];
    networkConfig = {
      DHCP = "yes";
      IPv6AcceptRA = true;
    };
  };

  time.timeZone = "Europe/Stockholm";
  i18n.defaultLocale = "en_US.UTF-8";

  # User account
  users.users.oumu = {
    isNormalUser = true;
    description = "Oumu Admin";
    extraGroups = [ "wheel" "networkmanager" ];
    packages = with pkgs; [
      git
      vim
      htop
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII6uq8nXD+QBMhXqRNywwCa/dl2VVvG/2nvkw9HEPFzn"
    ];
  };

  # Home Manager configuration for oumu user with nix-openclaw
  home-manager.users.oumu = { pkgs, ... }: {
    imports = [
      inputs.nix-openclaw.homeManagerModules.openclaw
    ];
    
    home.username = "oumu";
    home.homeDirectory = "/home/oumu";
    
    programs.openclaw = {
      enable = true;
      config = {
        gateway = {
          mode = "local";
          port = 8080;
        };
        # Telegram config - you'll need to set these up
        # channels.telegram = {
        #   tokenFile = "/home/oumu/.secrets/telegram-token";
        #   allowFrom = [ 123456789 ];
        # };
      };
      
      instances.default = {
        enable = true;
        package = pkgs.openclaw;
        stateDir = "/home/oumu/.openclaw";
        workspaceDir = "/home/oumu/.openclaw/workspace";
        launchd.enable = false; # Not macOS
      };
    };
    
    home.stateVersion = "24.11";
  };

  security.sudo.wheelNeedsPassword = false;

  environment.shellAliases = {
    rebuild-oumu = "sudo nixos-rebuild switch --flake ~/config#oumu";
    rebuild-test = "sudo nixos-rebuild test --flake ~/config#oumu";
  };

  environment.systemPackages = with pkgs; [
    git
    vim
    nano
    htop
    jq
    helix
    curl
    wget
    bind
    # Openclaw tools
    nodejs_20
    pnpm
  ];

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 8080 ];  # SSH and Openclaw gateway
    allowedUDPPorts = [];
  };

  fileSystems."/run/secrets/host" = {
    device = "host_share";
    fsType = "virtiofs";
    options = [ "ro" ];
  };

  systemd.services.install-deploy-key = {
    description = "Install deploy key from host share";
    after = [ "local-fs.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "oumu";
    };
    script = ''
      mkdir -p /home/oumu/.ssh
      chmod 700 /home/oumu/.ssh
      if [ -f /run/secrets/host/deploy_key ]; then
        cp /run/secrets/host/deploy_key /home/oumu/.ssh/id_ed25519
        chmod 600 /home/oumu/.ssh/id_ed25519
        chown oumu:users /home/oumu/.ssh/id_ed25519
        ssh-keyscan github.com > /home/oumu/.ssh/known_hosts
        chown oumu:users /home/oumu/.ssh/known_hosts
      fi
    '';
  };

  sops = {
    defaultSopsFile = ./secrets/secrets.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets = {};
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/oumu 0750 oumu oumu -"
    "d /var/lib/oumu/secrets 0700 oumu oumu -"
    "d /var/lib/oumu/data 0750 oumu oumu -"
    "d /home/oumu/.openclaw 0750 oumu oumu -"
    "d /home/oumu/.secrets 0700 oumu oumu -"
  ];

  system.stateVersion = "24.11";
}
