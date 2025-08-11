{
  modules,
  private-infra,
  config,
  pkgs,
  vars-helper,
  ...
}: {
  imports = with modules.nixosModules;
    [
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
      libvirt
      vfio
      fonts
      nvidia
      # restic
      docker
      steam
      k3s
    ]
    ++ (with vars-helper.nixosModules; [default])
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

  my.secrets.discover = {
    enable = true;
    dir = ../../vars/generators;
    includeTags = ["aws" "openai" "openrouter" "user"];
  };

  my.secrets.exposeUserSecrets = [
    {
      enable = true;
      secretName = "user-ssh-key";
      file = "key";
      user = config.my.mainUser.name;
      group = "users";
      dest = "/home/${config.my.mainUser.name}/.ssh/id_ed25519";
    }
    {
      enable = true;
      secretName = "user-age-key";
      file = "key";
      user = config.my.mainUser.name;
      group = "users";
      dest = "/home/${config.my.mainUser.name}/.config/sops/age/keys.txt";
    }
  ];

  my.secrets.allowReadAccess = [
    {
      readers = [config.my.mainUser.name];
      path = config.my.secrets.getPath "api-key-openai" "api_key";
    }
    {
      readers = [config.my.mainUser.name];
      path = config.my.secrets.getPath "api-key-openrouter" "api_key";
    }
    {
      readers = [config.my.mainUser.name];
      path = config.my.secrets.getPath "api-key-aws-access" "aws_access_key_id";
    }
    {
      readers = [config.my.mainUser.name];
      path = config.my.secrets.getPath "api-key-aws-secret" "aws_secret_access_key";
    }
  ];

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
    greeting = "Enter the heliosphere via charon!";
  };

  # Fix SATA power management issues during suspend, did not work
  # boot.kernelParams = [ "libata.force=noncq" ];
}
