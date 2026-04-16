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
      system-stylix
      atuin
      greetd
      nvidia
      fonts
      niri
      vfio
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
      ++ (with ctx.inputs.varsHelper.homeModules; [default])
      ++ (with ctx.inputs.privateInfra.homeModules; [
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

  time.timeZone = "Europe/Stockholm";

  environment.systemPackages = with pkgs; [
    devenv
    localsend
    iwd
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
    secrets = {
      discover = {
        enable = true;
        dir = ../../vars/generators;
        includeTags = ["aws" "openai" "openrouter" "user" "b2" "wifi"];
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
    firewall.trustedInterfaces = ["zt+"];
    networkmanager.enable = lib.mkForce true;

    # wpa_supplicant managed at runtime to keep PSK out of Nix store
    wireless.enable = false;
  };

  # Generate wpa_supplicant.conf at runtime from secrets
  systemd.services.generate-wpa-conf = {
    description = "Generate wpa_supplicant.conf from secrets";
    wantedBy = ["multi-user.target"];
    before = ["wpa-supplicant.service"];
    script = ''
      PSK=$(cat ${config.my.secrets.getPath "wifi-psk" "psk"})
      cat > /etc/wpa_supplicant.conf <<EOF
      ctrl_interface=/run/wpa_supplicant
      update_config=1
      network={
        ssid="g\xe5rdestorp"
        psk="$PSK"
        priority=10
      }
      network={
        ssid="g\xe5rdestorp-2"
        psk="$PSK"
        priority=5
      }
      EOF
      chmod 600 /etc/wpa_supplicant.conf
    '';
    serviceConfig.Type = "oneshot";
  };
}
