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
      system-stylix
      greetd
      nvidia
      fonts
      niri
      vfio
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
        bitwarden-client
        mail-clients-setup
        ssh
        niri
        xdg-mimeapps
        firefox
        node
      ]
      ++ (with vars-helper.homeModules; [default])
      ++ (with private-infra.homeModules; [
        mail-clients
        rbw
      ]);
    my = {
      programs = {
        mail = {
          clients = ["aerc"];
        };
        rbw = {
          pinentrySource = "gui";
        };
        rofi = {
          withRbw = true;
        };
        helix = {
          languages = ["nix" "markdown" "spellchecking"];
        };
      };

      waybar = {
        windowManager = "niri";
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
      {
        name = "z-claude";
        title = "z-claude";
        setTerminalTitle = true;
        command = "/home/p/.npm-global/bin/claude";
        environmentFile = config.my.secrets.getPath "z-ai-env" "env";
        useSystemdRun = false;
      }
    ];

    home.stateVersion = "25.11";
  };

  nixpkgs.config.allowUnfree = true;

  time.timeZone = "Europe/Stockholm";

  environment.systemPackages = with pkgs; [
    devenv
    localsend
    iwd
    steam
    moonlight-qt
  ];

  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  security.polkit.enable = true;
  my = {
    secrets = {
      discover = {
        enable = true;
        dir = ../../vars/generators;
        includeTags = ["aws" "openai" "openrouter" "user" "b2"];
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
      ];

      generateManifest = false;
    };

    mainUser.name = "p";

    greetd = {
      enable = true;
      greeting = "Enter the heliosphere via ariel!";
    };

    gui = {
      enable = true;
      session = "niri";
      terminal = "kitty";
    };
  };

  users.users.p.extraGroups = ["networkmanager"];

  networking = {
    # Allow localsend receive port
    firewall.allowedTCPPorts = [53317];
    networkmanager.enable = lib.mkForce true;

    wireless.enable = true;
    wireless.networks = {
      "gärdestorp-2" = {
        psk = "denna-kod-for-wifi";
        priority = 5;
      };
      "gärdestorp" = {
        psk = "denna-kod-for-wifi";
        priority = 10;
      };
    };
  };

  hardware.nvidia.package = lib.mkForce config.boot.kernelPackages.nvidiaPackages.legacy_470;
  nixpkgs.config.nvidia.acceptLicense = true;

  hardware.nvidia.prime = {
    intelBusId = "PCI:0:2:0";
    nvidiaBusId = "PCI:0:4:0";
  };
  services.libinput.enable = true;

  services.libinput.touchpad.disableWhileTyping = true;
}
