{
  modules,
  private-infra,
  config,
  pkgs,
  vars-helper,
  lib,
  playwrightMcpLatest,
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
      intel-gpu
      # nvidia
      docker
      steam
      k3s
      backups
      sunshine
      atuin
      codenomad
      rclone-s3
      auto-suspend
      wireguard-tunnels
      paperless-consumption-mount
      politikerstod-remote-worker
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
        voxtype
        wtp
        agent-browser
        sandboxed-binaries
        local-ai
        swayidle
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
      };

      waybar = {
        windowManager = "niri";
      };

      secrets.wrappedHomeBinaries = [
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

    programs.wtp = {
      enable = true;
      enableFishIntegration = true;
      enableFishCdWrapper = true;
    };

    programs.voxtype = {
      enable = true;
      model = "large-v3-turbo";
      # modelHash = "sha256-kh5M+Ghv3Zk9zQgaXaW2w2W/3hFi5ysI11rHUomSCx8=";
      enableService = true;
      enableVulkan = true;
    };

    programs.agent-browser = {
      enable = true;
    };

    my.swayidle = {
      enable = true;
      idleSeconds = 300; # 5 min no input -> mark session idle
    };

    home.stateVersion = "25.11";
  };
  my = {
    secrets = {
      discover = {
        enable = true;
        dir = ../../vars/generators;
        includeTags = ["aws" "charon" "openai" "openrouter" "user" "b2" "debug" "garage-s3" "wireguard-tunnels"];
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

    rclone-s3 = {
      enable = true;
      mountPoint = "/s3";
      bucket = "shared";
      endpoint = "http://10.0.0.1:3900";
      region = "garage";
      user = config.my.mainUser.name;
    };

    # Paperless consumption folder mount (drop files here to ingest)
    paperless-consumption-mount = {
      enable = true;
      mountPoint = "/paperless-consume";
      bucket = "paperless-consume";
      endpoint = "http://10.0.0.1:3900";
      region = "garage";
      user = config.my.mainUser.name;
    };

    backups = {
      documents = {
        enable = true;
        path = "/home/${config.my.mainUser.name}/documents";
        frequency = "daily";
        backends = {
          b2 = {
            type = "b2";
            lifecycleKeepPriorVersionsDays = 5;
          };
          garage = {
            type = "garage-s3";
          };
        };
        restore.backend = "garage";
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
      # gpuIds = "10de:1b81,10de:10f0";
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

    atuin.enable = true;

    codenomad = {
      enable = true;
      runAsMainUser = true;
      listenAddress = "0.0.0.0";
      port = 9898;
      skipAuth = true;
      unrestrictedRoot = false;
      workspaceRoot = "/home/p/repos";
      manageWorkspaceRoot = false;
      openFirewall = true;
    };

    # Auto-suspend when system is idle (load < threshold + no user input)
    autoSuspend = {
      enable = true;
      checkIntervalMinutes = 5;
      requiredIdleChecks = 3;
      loadThreshold = "2.0";
      userIdleSeconds = 600;
    };

    # Remote worker for politikerstod OCR/embeddings processing
    politikerstod-remote-worker = {
      enable = true;
      numWorkers = 8;
      workerTags = ["document_process"];
    };

    wireguardTunnels = {
      enable = true;
      tunnels = {
        genome-worktree-zenith = {
          activationPolicy = "manual"; # systemctl start wg-tunnel-genome-worktree-zenith
        };
        # nebula-crystal-forge = {
        #   activationPolicy = "up";  # Auto-start at boot
        # };
      };
    };
  };

  nixpkgs.config.allowUnfree = true;

  time.timeZone = "Europe/Stockholm";

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
    playwrightMcpLatest.legacyPackages.${pkgs.system}.playwright-mcp
    bun
    google-cloud-sdk
    amp-cli
  ];

  networking = {
    interfaces.enp4s0.wakeOnLan.enable = true;
    firewall.allowPing = true;
    # Allow localsend receive port
    # Allow 3000/1 and 5000/1 for dev server and tooling
    firewall.allowedTCPPorts = [53317 3000 3001 5000 5001];

    interfaces.enp4s0.ipv4.routes = [
      {
        address = "192.168.200.0";
        prefixLength = 24;
        via = "10.0.0.1";
      }
    ];
  };

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

  security.wrappers.intel_gpu_top = {
    owner = "root";
    group = "root";
    capabilities = "cap_sys_admin+ep";
    source = "${pkgs.intel-gpu-tools}/bin/intel_gpu_top";
  };

  powerManagement.enable = true;

  programs.virt-manager.enable = true;

  systemd.services.nix-daemon.serviceConfig = {
    Nice = lib.mkForce 15;
    IOSchedulingClass = lib.mkForce "idle";
    IOSchedulingPriority = lib.mkForce 7;
    LimitNOFILE = "infinity";
  };
  security.pam.loginLimits = [
    {
      domain = "*";
      item = "nofile";
      type = "-";
      value = "524288";
    }
  ];
}
