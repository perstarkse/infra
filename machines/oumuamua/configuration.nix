{
  modules,
  config,
  ...
}: {
  imports = with modules.nixosModules; [
    ./secrets.nix
    home-module
    sound
    options
    shared
    disko
    interception-tools
    system-stylix
    hyprland
    ledger
    # restic
  ];

  home-manager.users.${config.my.mainUser.name} = {
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

  my.mainUser.name = "p";

  my.userSecrets = [
    "mail-gmail-perstark-password/password"
    "mail-gmail-sprlkhick-password/password"
    "mail-disroot-mojotastic-password/password"
    "mail-stark-per-password/password"
    "mail-stark-work-password/password"
    "mail-stark-services-password/password"
    "api-key-openai/api_key"
    "api-key-openrouter/api_key"
    "api-key-aws-access/aws_access_key_id"
    "api-key-aws-secret/aws_secret_access_key"
  ];

  time.timeZone = "Europe/Stockholm";

  disko.devices.disk.main.device = "/dev/disk/by-id/ata-QEMU_HARDDISK_QM00001";

  users.users.root.openssh.authorizedKeys.keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII6uq8nXD+QBMhXqRNywwCa/dl2VVvG/2nvkw9HEPFzn p@charon"];

  clan.core.networking.zerotier.controller.enable = true;

  environment.systemPackages = [
    # pkgs.wget
  ];
}
