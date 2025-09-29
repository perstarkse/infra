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
      blinkstick
      system-stylix
      sway
      terminal
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
          languages = ["nix" "markdown" "rust" "jinja" "spellchecking"];
        };
      };

      waybar = {
        windowManager = "sway";
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
      ];
    };

    home.stateVersion = "25.11";
  };
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
      enable = true;
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
      session = "sway";
      terminal = "kitty";
    };
  };

  nixpkgs.config.allowUnfree = true;

  time.timeZone = "Europe/Stockholm";

  clan.core.networking.zerotier.controller.enable = true;

  environment.systemPackages = with pkgs; [
    code-cursor-fhs
    devenv
    localsend
    bluetuith
    codex
    discord
  ];

  # Allow localsend receive port
  networking.firewall.allowedTCPPorts = [53317];

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

  hardware.cpu.amd.updateMicrocode = true;

  powerManagement.enable = true;

  # boot.kernelParams = ["libata.noacpi=1" "mem_sleep_default=s2idle"];

  # boot.initrd.availableKernelModules = [
  #   "nvme"
  #   "xhci_pci"
  #   "ahci"
  #   "usbhid"
  #   "usb_storage"
  #   "sd_mod"
  # ];
  #
  # Did not work, fails entering suspend
  # boot.kernelParams = ["ahci.mobile_lpm_policy=0"];

  # Disable START STOP UNIT for the two Intel enterprise SSDs
  # services.udev.extraRules = ''
  #   ACTION=="add|change", SUBSYSTEM=="scsi_disk", KERNEL=="5:0:0:0|6:0:0:0", \
  #     ATTR{manage_start_stop}="0"
  # '';

  # services.udev.extraRules = ''
  #   # Intel enterprise SATA SSDs occasionally choke on STANDBY IMMEDIATE during suspend.
  #   ACTION=="add|change", SUBSYSTEM=="scsi_disk", \
  #     ATTRS{vendor}=="INTEL", ATTRS{model}=="SSDSC2KB03*", \
  #     ATTR{manage_start_stop}="0"
  # '';

  # Did not work
  # services.udev.extraRules = ''
  #   ACTION=="add", SUBSYSTEM=="scsi_host", KERNEL=="host*", ATTR{link_power_management_policy}="max_performance"
  # '';

  # Suspend hook — flip SATA LPM and (optionally) standby the Intel SSDs
  # systemd.services.pre-sleep-sata-lpm = {
  #   description = "Pre-Sleep (SATA LPM relax + SSD standby)";
  #   wantedBy = ["sleep.target"];
  #   before = ["sleep.target" "systemd-suspend.service"];
  #   serviceConfig.Type = "oneshot";
  #   # Ensure logger/hdparm are in PATH
  #   path = [pkgs.util-linux pkgs.hdparm];
  #   script = ''
  #     for pol in /sys/class/scsi_host/host*/link_power_management_policy; do
  #       echo max_performance > "$pol" || true
  #     done
  #   '';
  # };

  # # Resume hook — restore preferred LPM
  # systemd.services.resume-sata-lpm = {
  #   description = "Post-Resume (restore SATA LPM)";
  #   wantedBy = ["suspend.target" "hibernate.target" "hybrid-sleep.target"];
  #   after = ["suspend.target" "hibernate.target" "hybrid-sleep.target"];
  #   serviceConfig.Type = "oneshot";
  #   path = [pkgs.util-linux];
  #   script = ''
  #     for pol in /sys/class/scsi_host/host*/link_power_management_policy; do
  #       echo med_power_with_dipm > "$pol" || true
  #     done
  #     logger -t resume-sata-lpm "Restored LPM=med_power_with_dipm"
  #   '';
  # };
}
