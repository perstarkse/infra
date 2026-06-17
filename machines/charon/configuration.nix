{
  ctx,
  config,
  pkgs,
  lib,
  ...
}: let
  pinnedKernelPkgs = import (builtins.getFlake "github:NixOS/nixpkgs/afbbf774e2087c3d734266c22f96fca2e78d3620") {
    inherit (pkgs.stdenv.hostPlatform) system;
    config = {
      allowUnfree = true;
    };
  };
in {
  imports = with ctx.flake.nixosModules;
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
      attic-cache
      steam
      backups
      sunshine
      atuin
      codenomad
      openchamber
      opencode
      oh-my-opencode
      rclone-s3
      wake-proxy
      auto-suspend
      wireguard-tunnels
      paperless-consumption-mount
      politikerstod-remote-worker
      vpn-browser
      # steam-gamescope
    ]
    ++ (with ctx.inputs.varsHelper.nixosModules; [default])
    ++ (with ctx.inputs.privateInfra.nixosModules; [hello-service]);

  home-manager.users.${config.my.mainUser.name} = {
    imports = with ctx.flake.homeModules;
      [
        options
        sops
        noctalia
        helix
        rofi
        git
        direnv
        zoxide
        fish
        sccache
        kitty
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
        llm-agents-cli
        oh-my-opencode
        sandboxed-binaries
        local-ai
        swayidle
      ]
      ++ (with ctx.inputs.varsHelper.homeModules; [default])
      ++ (with ctx.inputs.privateInfra.homeModules; [
        mail-clients
        rbw
      ]);
    my = {
      sandboxedHomeBinaries = [
        {
          name = "sb-codex";
          program = "codex";
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
            "/home/p/.cache/sccache"
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
          languages = ["nix" "typst" "markdown" "rust" "jinja" "spellchecking" "fish"];
        };
      };

      noctalia = {
        enable = true;
      };

      secrets.wrappedHomeBinaries = [
        {
          name = "z-claude";
          title = "z-claude";
          setTerminalTitle = true;
          command = "claude";
          environmentFile = config.my.secrets.getPath "z-ai-env" "env";
          useSystemdRun = false;
        }
      ];
    };

    programs = {
      wtp = {
        enable = true;
        enableFishIntegration = true;
        enableFishCdWrapper = true;
      };

      voxtype = {
        enable = true;
        model.name = "large-v3-turbo";
        service.enable = true;
        package = ctx.inputs.voxtype.packages.${pkgs.stdenv.hostPlatform.system}.vulkan;
      };

      llm-agents = {
        enable = true;
        packages = [
          "opencode"
          "codex"
          "claude-code"
          "amp"
          "agent-browser"
        ];
      };

      oh-my-opencode = {
        enable = true;
        defaultConfigFile = ../../assets/opencode/oh-my-opencode.json;
        openagentConfigFile = ../../assets/opencode/oh-my-openagent.json;
      };

      fish.interactiveShellInit = lib.mkAfter ''
        set -gx OPENCODE_OMO_URL http://127.0.0.1:4098
      '';
    };

    my.swayidle = {
      enable = true;
      idleSeconds = 300; # 5 min no input -> mark session idle
    };

    home.stateVersion = "25.11";
  };
  services.wakeproxy = {
    enable = false;
    keepAwake = {
      maxDurationSeconds = 14400;
      sshTarget = {
        enable = true;
        authorizedKeysFile = config.my.secrets.getPath "wake-proxy-keep-awake-ssh" "public_key";
      };
    };
  };

  my = {
    listenNetworkAddress = "10.0.0.15";

    attic-cache.client = {
      enable = true;
      endpoint = "http://10.0.0.10:8092";
      serverName = "makemake";
      cacheName = "heliosphere";
      autoPush = true;
      tokenFileName = "charon-token";
    };

    secrets = {
      discover = {
        enable = true;
        dir = ../../vars/generators;
        includeTags = ["aws" "charon" "openai" "openrouter" "openchamber" "user" "b2" "debug" "garage-s3" "wireguard-tunnels" "keep-awake" "attic-cache"];
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
          readers = ["oh-my-opencode"];
          path = config.my.secrets.getPath "context7" "env";
        }
        {
          readers = ["oh-my-opencode"];
          path = config.my.secrets.getPath "api-key-openrouter" "api_key";
        }
        {
          readers = ["oh-my-opencode"];
          path = config.my.secrets.getPath "api-key-openai" "api_key";
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
        {
          readers = ["politikerstod-worker-lekeberg"];
          path = config.my.secrets.getPath "politikerstod-lekeberg" "env";
        }
        {
          readers = ["politikerstod-worker-orebro"];
          path = config.my.secrets.getPath "politikerstod-orebro" "env";
        }
      ];

      generateManifest = false;
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
      enable = false;
      runAsMainUser = true;
      listenAddress = "0.0.0.0";
      port = 9898;
      skipAuth = true;
      unrestrictedRoot = false;
      workspaceRoot = "/home/p/repos";
      manageWorkspaceRoot = false;
      openFirewall = true;
    };

    openchamber = {
      enable = true;
      useOpencode = true;
      runAsMainUser = true;
      listenAddress = "0.0.0.0";
      port = 3000;
      projectId = "charon";
      projectPath = "/home/p/repos";
      projectLabel = "charon";
      openFirewall = true;
      allowedFirewallSources = [
        "10.0.0.1"
        "10.0.0.15"
      ];
    };

    opencode = {
      enable = true;
      skillSources = [
        {
          name = "rust-skills";
          path = ctx.inputs.rust-skills;
        }
        {
          name = "nixos-deployment";
          path = ../../assets/opencode/skills/nixos-deployment;
        }
        {
          name = "nixos-service-module";
          path = ../../assets/opencode/skills/nixos-service-module;
        }
        {
          name = "nixos-secrets";
          path = ../../assets/opencode/skills/nixos-secrets;
        }
        {
          name = "rust-nix-crane";
          path = ../../assets/opencode/skills/rust-nix-crane;
        }
      ];
      agentSourceDir = ../../assets/opencode/agents;
      defaultConfigFile = ../../assets/opencode/opencode-shared.json;
      environmentFile = config.my.secrets.getPath "context7" "env";
    };

    oh-my-opencode = {
      enable = true;
      port = 4098;
      reposPath = "/home/p/repos";
      defaultConfigFile = ../../assets/opencode/oh-my-opencode.json;
      environmentFile = config.my.secrets.getPath "context7" "env";
    };

    # Auto-suspend when system is idle (load < threshold + no user input)
    autoSuspend = {
      enable = true;
      checkIntervalMinutes = 6;
      requiredIdleChecks = 3;
      loadThreshold = "6.0";
      userIdleSeconds = 600;
    };

    # Remote worker for politikerstod OCR/embeddings processing
    politikerstod-remote-worker = {
      instances = {
        lekeberg = {
          enable = true;
          numWorkers = 8;
          workerTags = ["document_process"];
          s3.bucket = "politikerstod";
          s3.prefix = "lekeberg";
          scraper.baseUrl = "https://meetings.lekeberg.se";
        };

        orebro = {
          enable = true;
          numWorkers = 8;
          workerTags = ["document_process"];
          s3.prefix = "orebro";
          scraper.baseUrl = "https://politiskamoten.regionorebrolan.se/";
          database = {
            host = "10.0.0.10";
            port = 5433;
            name = "politikerstod_orebro";
            user = "politikerstod_orebro";
          };
        };
      };
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

    vpn-browser = {
      enable = true;
    };
  };

  # Battlemage + xe is currently stable on 6.12.74 here; newer 6.12.x regressed GPU init.
  boot.kernelPackages = pinnedKernelPkgs.linuxPackages;

  time.timeZone = "Europe/Stockholm";

  environment.systemPackages = with pkgs; [
    unstable.code-cursor-fhs
    devenv
    localsend
    bluetuith
    discord
    unstable.prismlauncher
    virt-manager
    gamescope
    bun
    google-cloud-sdk
  ];

  networking = {
    interfaces.enp4s0.wakeOnLan.enable = true;
    firewall.allowPing = true;
    # Allow localsend receive port
    # Allow 3000/1 and 5000/1 for dev server and tooling
    firewall.allowedTCPPorts = [53317 3001 5000 5001];
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

  systemd.services.bluetooth-resume-recover = {
    description = "Recover Bluetooth after resume";
    wantedBy = ["suspend.target" "hibernate.target" "hybrid-sleep.target" "suspend-then-hibernate.target"];
    after = ["suspend.target" "hibernate.target" "hybrid-sleep.target" "suspend-then-hibernate.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "bluetooth-resume-recover" ''
        set -euo pipefail
        ${pkgs.coreutils}/bin/sleep 3
        ${pkgs.systemd}/bin/systemctl try-restart bluetooth.service
        ${pkgs.bluez}/bin/bluetoothctl power on >/dev/null 2>&1 || true
      '';
    };
  };

  security = {
    polkit.enable = true;

    wrappers.intel_gpu_top = {
      owner = "root";
      group = "root";
      capabilities = "cap_sys_admin+ep";
      source = "${pkgs.intel-gpu-tools}/bin/intel_gpu_top";
    };

    pam.loginLimits = [
      {
        domain = "*";
        item = "nofile";
        type = "-";
        value = "524288";
      }
    ];
  };

  hardware.cpu.amd.updateMicrocode = true;

  powerManagement.enable = true;

  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;

  programs.virt-manager.enable = true;

  systemd.services.nix-daemon.serviceConfig = {
    Nice = lib.mkForce 15;
    IOSchedulingClass = lib.mkForce "idle";
    IOSchedulingPriority = lib.mkForce 7;
    LimitNOFILE = "infinity";
  };
}
