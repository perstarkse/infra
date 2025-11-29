{
  modules,
  private-infra,
  config,
  pkgs,
  vars-helper,
  lib,
  ...
}: {
  imports = with modules.nixosModules;
    [
      home-module
      sound
      options
      shared
      interception-tools
      blinkstick
      system-stylix
      niri
      terminal
      greetd
      ledger
      vfio
      libvirt
      fonts
      nvidia
      docker
      steam
      k3s
      backups
      sunshine
      # steam-gamescope
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
        sccache
        kitty
        dunst
        ncspot
        zellij
        starship
        qutebrowser
        looking-glass-client
        bitwarden-client
        blinkstick
        mail-clients-setup
        ssh
        xdg-mimeapps
        xdg-userdirs
        firefox
        chromium
        niri
        node
        wtp
        sandboxed-binaries
      ]
      ++ (with vars-helper.homeModules; [default])
      ++ (with private-infra.homeModules; [
        mail-clients
        rbw
      ]);
    my = {
      sandboxedHomeBinaries = [
        {
          name = "sb-codex";
          program = "/home/p/.npm-global/bin/codex";
          defaultArgs = [
            "--sandbox"
            "danger-full-access"
            "--ask-for-approval"
            "never"
          ];

          bindCwd = true;
          enableRustCache = true;
          allowNetwork = true;

          extraWritableDirs = [
            "/home/p/.npm-global"
            # "/home/p/.npm"
            "/home/p/.cache/sccache"
            # "/home/p/.config"
            "/home/p/.codex"
            "/home/p/.nix-profile/bin"
          ];
        }
      ];

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
          languages = ["nix" "typst" "markdown" "rust" "jinja" "spellchecking"];
        };
        wtp = {
          enable = true;
          enableFishIntegration = true;
          enableFishCdWrapper = true;
        };
      };

      waybar = {
        windowManager = "niri";
      };

      secrets.wrappedHomeBinaries = [
        {
          name = "mods";
          title = "Mods";
          setTerminalTitle = true;
          command = "${pkgs.mods}/bin/mods";
          envVar = "OPENAI_API_KEY";
          secretPath = config.my.secrets.getPath "api-key-openai" "api_key";
          useSystemdRun = true;
        }
        {
          name = "z-claude";
          title = "z-claude";
          setTerminalTitle = true;
          command = "/home/p/.npm-global/bin/claude";
          environmentFile = config.my.secrets.getPath "z-ai-env" "env";
          useSystemdRun = false;
        }
      ];
    };

    home.stateVersion = "25.11";
  };
  my = {
    secrets = {
      discover = {
        enable = true;
        dir = ../../vars/generators;
        includeTags = ["aws" "charon" "openai" "openrouter" "user" "b2"];
      };

      exposeUserSecrets = [
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

      allowReadAccess = [
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
        {
          readers = [config.my.mainUser.name];
          path = config.my.secrets.getPath "z-ai-env" "env";
        }
      ];

      generateManifest = true;
    };

    backups = {
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

    mainUser.name = "p";

    libvirtd = {
      enable = true;
      spiceUSBRedirection = true;

      shutdownOnSuspend = {
        enable = true;
        vms = ["win11-gaming"];
      };

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

    vfio = {
      enable = false;
      gpuIds = "10de:1b81,10de:10f0";
      hugepages = 20;
      kvmfrStaticSizeMb = 128;
    };

    k3s = {
      enable = false;
      initServer = false;
      serverAddrs = ["https://10.0.0.1:6443"];
      tlsSan = "10.0.0.1";
    };

    greetd = {
      enable = true;
      greeting = "Enter the heliosphere via charon!";
    };

    gui = {
      enable = true;
      session = "niri";
      terminal = "kitty";
    };
  };

  nixpkgs.config.allowUnfree = true;

  time.timeZone = "Europe/Stockholm";

  # clan.core.networking.zerotier.controller.enable = true;

  environment.systemPackages = with pkgs; [
    code-cursor-fhs
    devenv
    localsend
    bluetuith
    codex
    discord
    prismlauncher
    virt-manager
    gamescope
  ];

  # Allow localsend receive port
  networking.firewall.allowedTCPPorts = [53317];

  # services.blueman.enable = true;
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

  security.polkit.enable = true;

  hardware.cpu.amd.updateMicrocode = true;

  powerManagement.enable = true;

  systemd.services.nix-daemon.serviceConfig = {
    Nice = lib.mkForce 15;
    IOSchedulingClass = lib.mkForce "idle";
    IOSchedulingPriority = lib.mkForce 7;
  };
}
