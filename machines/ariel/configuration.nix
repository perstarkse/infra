{
  ctx,
  config,
  pkgs,
  lib,
  ...
}: {
  imports = with ctx.flake.nixosModules;
    [
      home-module
      sound
      options
      shared
      interception-tools
      stylix
      atuin
      greetd
      nvidia
      fonts
      niri
    ]
    ++ (with ctx.inputs.varsHelper.nixosModules; [default])
    ++ (with ctx.inputs.privateInfra.nixosModules; [hello-service]);

  home-manager.users.${config.my.mainUser.name} = {
    imports = with ctx.flake.homeModules;
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
        nix-scaffold
        zellij
        starship
        qutebrowser
        bitwarden-client
        mail
        ssh
        niri
        xdg-mimeapps
        firefox
        node
        llm-agents-cli
      ]
      ++ (with ctx.inputs.varsHelper.homeModules; [default])
      ++ (with ctx.inputs.privateInfra.homeModules; [
        mail-clients
        rbw
      ]);
    my = {
      programs = {
        rbw = {
          pinentrySource = "gui";
        };
        mail = {
          enable = true;
          clients = ["aerc"];
        };
      };

      qutebrowser = {
        enable = true;
      };

      # Home module enables (converted from always-on to my.<x>.enable)
      bitwarden-client.enable = true;
      direnv.enable = true;
      dunst.enable = true;
      firefox.enable = true;
      fish.enable = true;
      git.enable = true;
      ncspot.enable = true;
      nix-scaffold.enable = true;
      node.enable = true;
      ssh.enable = true;
      starship.enable = true;
      xdg-mimeapps.enable = true;
      zellij.enable = true;
      zoxide.enable = true;

      rofi = {
        enable = true;
        withRbw = true;
      };

      helix = {
        enable = true;
        languages = ["nix" "markdown" "spellchecking"];
      };

      waybar = {
        enable = true;
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
        command = "claude";
        environmentFile = config.my.secrets.getPath "z-ai-env" "env";
        useSystemdRun = false;
      }
    ];

    my.llm-agents-cli = {
      enable = true;
      packages = ["claude-code"];
    };
  };

  time.timeZone = "Europe/Stockholm";

  environment.systemPackages = with pkgs; [
    devenv
    localsend
    steam
    moonlight-qt
  ];

  hardware = {
    bluetooth.enable = true;
    nvidia.package = lib.mkForce config.boot.kernelPackages.nvidiaPackages.legacy_470;
    nvidia.prime = {
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:0:4:0";
    };
  };

  services = {
    blueman.enable = true;
    libinput = {
      enable = true;
      touchpad.disableWhileTyping = true;
    };
  };

  security.polkit.enable = true;
  my = {
    atuin.enable = true;

    stylix.enable = true;
    interception-tools.enable = true;
    fonts.enable = true;
    nvidia.enable = true;
    sound.enable = true;
    secrets = {
      discover = {
        enable = true;
        dir = ../../vars/generators;
        includeTags = ["aws" "openai" "openrouter" "user" "b2" "journal-upload"];
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
    mainUser.extraSshKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII6uq8nXD+QBMhXqRNywwCa/dl2VVvG/2nvkw9HEPFzn p@charon"
    ];

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

  # Stream the journal to io's mTLS journal-remote so sshd fail2ban on the
  # router also covers this workstation.
  services.journald.upload = {
    enable = true;
    settings = {
      Upload = {
        URL = "https://10.0.0.1:19532";
        ServerKeyFile = toString (config.my.secrets.getPath "journal-upload" "client.key");
        ServerCertificateFile = toString (config.my.secrets.getPath "journal-upload" "client.pem");
        TrustedCertificateFile = toString (config.my.secrets.getPath "journal-upload" "ca.pem");
      };
    };
  };

  # The mTLS client key is root-only; run the uploader as root.
  systemd.services.systemd-journal-upload.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = lib.mkForce "root";
  };

  networking = {
    # Allow localsend receive port
    firewall.allowedTCPPorts = [53317];
    firewall.trustedInterfaces = ["zt+"];
    networkmanager.enable = lib.mkForce true;
  };
}
