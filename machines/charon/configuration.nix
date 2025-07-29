{
  modules,
  private-infra,
  config,
  pkgs,
  ...
}: {
  imports = with modules.nixosModules;
    [
      ../../secrets.nix
      ./hardware-configuration.nix
      ./boot.nix
      home-module
      sound
      options
      shared
      interception-tools
      system-stylix
      hyprland
      ledger
      user-ssh-keys
      user-age-key
      vfio
      fonts
      nvidia
      # restic
    ]
    ++ (with private-infra.nixosModules; [hello-service]);

  home-manager.users.${config.my.mainUser.name} = {
    imports = with modules.homeModules;
      [
        options
        hyprland
        helix
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
        mail-clients-setup
        ssh
        xdg-mimeapps
      ]
      ++ (with private-infra.homeModules; [
        mail-clients
        sops-infra
        rbw
      ]);
    my = {
      secrets = config.my.sharedSecretPaths;

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

  nixpkgs.config.allowUnfree = true;

  my.mainUser.name = "p";

  my.vfio = {
    enable = true;
    gpuIds = "10de:1b81,10de:10f0";
    hugepages = 20;
    kvmfrStaticSizeMb = 128;
  };

  my.userSecrets = [
    "api-key-openai/api_key"
    "api-key-openrouter/api_key"
    "api-key-aws-access/aws_access_key_id"
    "api-key-aws-secret/aws_secret_access_key"
  ];

  time.timeZone = "Europe/Stockholm";

  clan.core.networking.zerotier.controller.enable = true;

  environment.systemPackages = with pkgs; [
    virt-manager
    # pkgs.epy
  ];

  hardware.bluetooth.enable = true;
  services.blueman.enable = true;
}
