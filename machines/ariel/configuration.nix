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
      fonts
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
          clients = ["aerc"];
        };
        rbw = {
          pinentrySource = "gui";
        };
        rofi = {
          withRbw = true;
        };
        helix = {
          languages = ["nix" "markdown"];
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

  nixpkgs.config.allowUnfree = true;

  my.mainUser.name = "p";

  time.timeZone = "Europe/Stockholm";

  clan.core.networking.zerotier.controller.enable = true;

  environment.systemPackages = with pkgs; [
    devenv
    localsend
    iwd
  ];

  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  security.polkit.enable = true;

  my.greetd = {
    enable = true;
    greeting = "Enter the heliosphere via ariel!";
  };

  my.gui = {
    enable = true;
    session = "sway";
    terminal = "kitty";
  };

  # Allow localsend receive port
  networking.firewall.allowedTCPPorts = [53317];

  networking.wireless.enable = true;
  networking.wireless.networks = {
  };
}
