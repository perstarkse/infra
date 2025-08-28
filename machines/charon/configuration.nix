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
      docker
      steam
      k3s
      backups
    ]
    ++ (with vars-helper.nixosModules; [default])
    ++ (with private-infra.nixosModules; [hello-service]);

  home-manager.users.${config.my.mainUser.name} = {
    imports = with modules.homeModules;
      [
        options
        sops
        waybar
        helix
        rofi
        git
        direnv
        zoxide
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
      ++ (with vars-helper.homeModules; [default])
      ++ (with private-infra.homeModules; [
        mail-clients
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

    my.secrets.wrappedHomeBinaries = [
      {
        name = "mods";
        title = "Mods";
        setTerminalTitle = true;
        command = "${pkgs.mods}/bin/mods";
        envVar = "OPENAI_API_KEY";
        secretPath = config.my.secrets.getPath "api-key-openai" "api_key";
        useSystemdRun = true;
      }
    ];

    home.stateVersion = "25.11";
  };

  my.secrets.discover = {
    enable = true;
    dir = ../../vars/generators;
    includeTags = ["aws" "openai" "openrouter" "user" "b2"];
  };

  my.secrets.exposeUserSecrets = [
    {
      enable = true;
      secretName = "user-ssh-key";
      file = "key";
      user = config.my.mainUser.name;
      dest = "/home/${config.my.mainUser.name}/.ssh/id_ed25519";
    }
    {
      enable = true;
      secretName = "user-age-key";
      file = "key";
      user = config.my.mainUser.name;
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

  my.secrets.generateManifest = false;

  my.backups = {
    documents = {
      enable = true;
      path = "/home/${config.my.mainUser.name}/documents";
      frequency = "daily";
      backend = {
        type = "b2";
        bucket = null;
        lifecycleKeepPriorVersionsDays = 5;
      };
    };
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

  time.timeZone = "Europe/Stockholm";

  clan.core.networking.zerotier.controller.enable = true;

  environment.systemPackages = with pkgs; [
    code-cursor-fhs
    devenv
    localsend
    bluetuith
  ];

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Experimental = true;
        FastConnectable = true;
      };
      Policy = {
        AutoEnable = true;
      };
    };
  };

  # services.blueman.enable = true;

  security.polkit.enable = true;

  my.greetd = {
    enable = true;
    greeting = "Enter the heliosphere via charon!";
  };

  my.gui = {
    enable = true;
    session = "sway";
  };

  # Allow localsend receive port
  networking.firewall.allowedTCPPorts = [53317];

  boot.kernelParams = [
    "ahci.mobile_lpm_policy=0"
  ];
  # Fix SATA power management issues during suspend, did not work
  # boot.kernelParams = [ "libata.force=noncq" ];
}
