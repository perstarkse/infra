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
      sway
      greetd
      ledger
      user-ssh-keys
      user-age-key
      libvirt
      vfio
      fonts
      nvidia
      restic
      docker
      steam
      k3s
    ]
    ++ (with private-infra.nixosModules; [hello-service]);



  home-manager.users.${config.my.mainUser.name} = {
    imports = with modules.homeModules;
      [
        options
        waybar
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
        firefox
        sway
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
          pinentrySource = "gui";
        };
        rofi = {
          withRbw = true;
        };
        helix = {
          languages = ["nix" "markdown" "rust" "jinja"];
        };
      };

      waybar = {
        windowManager = "sway";
      };
    };

    home.stateVersion = "25.11";
  };

  nixpkgs.config.allowUnfree = true;

  my.mainUser.name = "p";

  my.libvirtd = {
    enable = true;
    spiceUSBRedirection = true;

    networks = [
      {
        name = "vm-nat";
        uuid = "80c19792-39ed-5c58-01b2-56ccfbac0b6b";
        mode = "nat";
        subnet = "192.168.101.0/24";
        gateway = "192.168.101.1";
        dhcpStart = "192.168.101.10";
        dhcpEnd = "192.168.101.254";
        firewallPorts = {
          tcp = [22 80 443];
          udp = [53];
        };
      }
      {
        name = "vm-isolated";
        uuid = "90d2a8a3-4afe-6d69-12c3-67dd0cbd1c7c";
        mode = "isolated";
        firewallPorts = {
          tcp = [];
          udp = [];
        };
      }
    ];
  };

  my.vfio = {
    enable = true;
    gpuIds = "10de:1b81,10de:10f0";
    hugepages = 20;
    kvmfrStaticSizeMb = 128;
  };

  my.k3s = {
    enable = false;
    initServer = false;
    serverAddrs = ["https://10.0.0.1:6443"];
    tlsSan = "10.0.0.1";
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
    code-cursor-fhs
    devenv
    localsend
  ];

  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  security.polkit.enable = true;

  my.greetd = {
    enable = true;
    sessionType = "sway";
    greeting = "Welcome to charon!";
  };

  # Fix SATA power management issues during suspend
  boot.kernelParams = [ "libata.force=noncq" ];
}
