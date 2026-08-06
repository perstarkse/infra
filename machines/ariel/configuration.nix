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
      journal-upload
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

      # Home module enables
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
    ];
  };

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
    fonts.enable = true;
    nvidia.enable = true;
    sound.enable = true;
    secrets = {
      discover = {
        enable = true;
        includeTags = ["aws" "openai" "openrouter" "user" "b2" "journal-upload"];
      };
    };

    mainUser.name = "p";
    mainUser.extraSshKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII6uq8nXD+QBMhXqRNywwCa/dl2VVvG/2nvkw9HEPFzn p@charon"
    ];

    greetd = {
      enable = true;
      greeting = "Enter the heliosphere via ariel!";
    };

    journalUpload.enable = true;

    gui = {
      enable = true;
    };
  };

  networking = {
    # Allow localsend receive port
    firewall.allowedTCPPorts = [53317];
    firewall.trustedInterfaces = ["zt+"];
    networkmanager.enable = lib.mkForce true;
  };
}
