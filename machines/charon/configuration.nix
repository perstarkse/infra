{
  ctx,
  config,
  pkgs,
  lib,
  ...
}: let
  # Battlemage + xe is stable on this kernel branch; newer 6.12.x regressed GPU init.
  # Pinned via the locked `nixpkgs-612` input instead of builtins.getFlake so
  # evals work offline and the pin stays in flake.lock.
  pinnedKernelPkgs = import ctx.inputs.nixpkgs612 {
    localSystem = {inherit (pkgs.stdenv.hostPlatform) system;};
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
      stylix
      niri
      terminal
      greetd
      ledger
      libvirt
      fonts
      intel-gpu
      ddcutil
      bluetooth-resume
      docker
      attic-cache
      journal-upload
      steam
      backups
      sunshine
      atuin
      sccache-daemon
      rclone-s3
      wake-proxy
      auto-suspend
      storage-alerts
      wireguard-tunnels
      paperless-consumption-mount
      politikerstod-remote-worker
      vpn-browser
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
        nix-scaffold
        zellij
        starship
        qutebrowser
        bitwarden-client
        blinkstick
        mail
        ssh
        xdg-mimeapps
        xdg-userdirs
        firefox
        chromium
        niri
        node
        voxtype
        wtp
        local-ai
        swayidle
        wow-launcher
      ]
      ++ (with ctx.inputs.varsHelper.homeModules; [default])
      ++ (with ctx.inputs.privateInfra.homeModules; [
        mail-clients
        rbw
      ])
      ++ (with ctx.inputs.agentTooling.homeModules; [
        pi-agent
        pi-web
        shared-skills
      ]);

    home.packages = [
      pkgs.agent-browser
    ];

    my = {
      programs = {
        rbw = {
          pinentrySource = "gui";
        };
        mail = {
          enable = true;
          clients = ["aerc" "thunderbird"];
        };
      };

      qutebrowser = {
        enable = true;
      };

      bitwarden-client.enable = true;
      blinkstick.enable = true;
      chromium.enable = true;
      direnv.enable = true;
      firefox.enable = true;
      fish.enable = true;
      git.enable = true;
      local-ai.enable = true;
      ncspot.enable = true;
      nix-scaffold.enable = true;
      node.enable = true;
      sccache.enable = true;
      ssh.enable = true;
      starship.enable = true;
      voxtype.enable = true;
      xdg-mimeapps.enable = true;
      xdg-userdirs.enable = true;
      zellij.enable = true;
      zoxide.enable = true;
      wow-launcher.enable = true;

      rofi = {
        enable = true;
        withRbw = true;
      };

      helix = {
        enable = true;
        languages = ["nix" "typst" "markdown" "rust" "jinja" "json" "spellchecking" "fish"];
      };

      noctalia = {
        enable = true;
      };

      agentTooling = {
        pi-agent = {
          permissionSystem.enable = false;
          enable = true;
          shellAlias = "PI_FFF_MODE=override command pi";
          defaultProvider = "cline-pass";
          defaultModel = "deepseek/deepseek-v4-flash";
          extraPackages = ["/home/p/repos/pi-cline-provider"];
          models = {
            providers.openrouter.models = [
              {
                id = "tencent/hy3:free";
                name = "Tencent Hy3 (Free)";
                reasoning = true;
                input = ["text"];
                cost = {
                  input = 0;
                  output = 0;
                  cacheRead = 0;
                  cacheWrite = 0;
                };
                contextWindow = 202144;
                maxTokens = 202144;
                compat = {
                  thinkingFormat = "openrouter";
                  supportsDeveloperRole = false;
                };
              }
            ];
          };
          subagentOverrides = lib.genAttrs ["scout" "context-builder" "planner" "researcher" "reviewer" "delegate"] (_: {
            model = "opencode/deepseek-v4-flash-free";
            fallbackModels = ["deepseek/deepseek-v4-flash"];
            defaultContext = "fresh";
            systemPromptMode = "append";
            systemPrompt = "You are a fresh subagent with zero inherited context. Your only knowledge comes from the task message and the tools you use. Gather all necessary context yourself. Do not assume prior knowledge.";
          });
          mcpServers = {
            accounted = {
              url = "https://accounting.lan.stark.pub/api/extensions/ext/mcp-server/mcp?client=pi-code";
              auth = "bearer";
              bearerToken = "!cat ${config.my.secrets.getPath "accounted-mcp-key" "env"} | grep '^ACCOUNTED_MCP_API_KEY=' | cut -d= -f2";
              lifecycle = "lazy";
            };
            context7 = {
              url = "https://mcp.context7.com/mcp";
              lifecycle = "lazy";
              headers = {
                CONTEXT7_API_KEY = "!cat ${config.my.secrets.getPath "context7" "env"} | grep '^CONTEXT7_API_KEY=' | cut -d= -f2";
              };
            };
            digikey = {
              # MyLists tools need the app subscribed to MyLists in the portal and its
              # OAuth Callback URL set to DIGIKEY_CALLBACK_URL below; the account owner
              # then runs the one-time mylists_authorize consent flow.
              command = "${ctx.inputs.digikeyMcp.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/digikey-mcp";
              lifecycle = "lazy";
              env = {
                DIGIKEY_CLIENT_ID = "!cat ${config.my.secrets.getPath "digikey" "env"} | grep '^DIGIKEY_CLIENT_ID=' | cut -d= -f2";
                DIGIKEY_CLIENT_SECRET = "!cat ${config.my.secrets.getPath "digikey" "env"} | grep '^DIGIKEY_CLIENT_SECRET=' | cut -d= -f2";
                DIGIKEY_CALLBACK_URL = "https://localhost:8139/digikey_callback";
                DIGIKEY_TOKEN_STORE = "/home/p/.local/state/digikey-mcp/tokens.json";
              };
            };
          };
        };
        pi-web = {
          enable = true;
          host = "0.0.0.0";
          pathAccess.allowedPaths = [
            "~/repos"
            "/mnt/sdb/repos"
            "/home/p/repos"
          ];
        };
        shared-skills = {
          enable = true;
        };
      };
    };

    programs = {
      voxtype = {
        enable = true;
        model.name = "large-v3-turbo";
        service.enable = true;
        package = ctx.inputs.voxtype.packages.${pkgs.stdenv.hostPlatform.system}.vulkan;
      };
    };

    my.wtp = {
      enable = true;
      enableFishIntegration = true;
      enableFishCdWrapper = true;
    };

    my.swayidle = {
      enable = true;
      idleSeconds = 300; # 5 min no input -> mark session idle
      lockOnSuspend = false;
    };
  };

  my = {
    stylix.enable = true;

    docker.enable = true;
    fonts.enable = true;
    intel-gpu.enable = true;
    sound.enable = true;
    steam.enable = true;
    sunshine.enable = true;
    ledger.enable = true;

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
        includeTags = ["aws" "charon" "openai" "openrouter" "context7" "user" "b2" "debug" "garage-s3" "wireguard-tunnels" "keep-awake" "attic-cache" "accounted-mcp" "digikey" "db-passwords" "journal-upload" "ntfy"];
      };

      allowReadAccess = [
        {
          readers = [config.my.mainUser.name];
          path = config.my.secrets.getPath "z-ai-env" "env";
        }
        {
          readers = [config.my.mainUser.name];
          path = config.my.secrets.getPath "accounted-mcp-key" "env";
        }
        {
          readers = [config.my.mainUser.name];
          path = config.my.secrets.getPath "context7" "env";
        }
        {
          readers = [config.my.mainUser.name];
          path = config.my.secrets.getPath "digikey" "env";
        }
        {
          readers = ["politikerstod-worker-lekeberg"];
          path = config.my.secrets.getPath "politikerstod-lekeberg" "env";
        }
        {
          readers = ["politikerstod-worker-lekeberg"];
          path = config.my.secrets.getPath "db-passwords" "politikerstod";
        }
        # Add back again when deploying politikerstod-orebro again
        # {
        #   readers = ["politikerstod-worker-orebro"];
        #   path = config.my.secrets.getPath "politikerstod-orebro" "env";
        # }
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
    mainUser.extraSshKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII6uq8nXD+QBMhXqRNywwCa/dl2VVvG/2nvkw9HEPFzn p@charon"
    ];

    libvirt = {
      enable = true;
      spiceUSBRedirection = true;

      shutdownOnSuspend = {
        enable = true;
        vms = ["win11"];
      };

      # Dir-backed pool so NixVirt creates win11-new.qcow2 on activation if missing.
      pools = [
        {
          name = "vm-disks";
          uuid = "b1a7e4d2-9f33-4c71-8e2a-6d5b0c9f1a47";
          path = "/mnt/sdb/disks";
          volumes = [
            {
              name = "win11-new.qcow2";
              capacity = {
                count = 80;
                unit = "GiB";
              };
              format = "qcow2";
            }
          ];
        }
      ];

      domains = [
        {
          name = "win11";
          uuid = "8c4d2bf3-3e6e-4c9b-a012-4b7c1e6f8d02";
          template = "windows";
          memory = {
            count = 8;
            unit = "GiB";
          };
          storageVol = "/mnt/sdb/disks/win11-new.qcow2";
          installVol = "/mnt/sdb/iso/win11.iso";
          networkName = "vm-nat";
          macAddress = "52:54:00:8e:11:02";
          nvramPath = "/var/lib/libvirt/qemu/nvram/win11-new_VARS.fd";
          virtioNet = true;
          virtioDrive = true;
          virtioVideo = true;
          installVirtio = true;
        }
      ];

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
          subnet = "192.168.123.0/24";
          gateway = "192.168.123.1";
          dhcpStart = "192.168.123.10";
          dhcpEnd = "192.168.123.254";
          firewallPorts = {
            tcp = [];
            udp = [];
          };
        }
      ];
    };

    greetd = {
      enable = true;
      greeting = "Enter the heliosphere via charon!";
    };

    gui = {
      enable = true;
    };

    atuin.enable = true;

    sccache-daemon = {
      enable = true;
    };

    # Auto-suspend when system is idle (load < threshold + no user input)
    auto-suspend = {
      enable = true;
      checkIntervalMinutes = 6;
      loadThreshold = "6.0";
    };

    # Capacity/SMART alerts: the root btrfs volume is at 88 % (warn threshold
    # is 85 %), so the first health check fires a ntfy alert into the
    # storage-alerts topic.
    storage-alerts = {
      enable = true;
      ntfy = {
        serverUrl = "https://ntfy.lan.stark.pub";
        topic = "storage-alerts";
        tokenFile = config.my.secrets.getPath "ntfy" "storage-token";
        tags = ["warning" "floppy_disk" "charon"];
      };
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
          database.passwordFile = config.my.secrets.getPath "db-passwords" "politikerstod";
        };

        orebro = {
          enable = false;
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

    wireguard-tunnels = {
      enable = true;
      tunnels = {
        genome-worktree-zenith = {
          activationPolicy = "manual"; # systemctl start wg-tunnel-genome-worktree-zenith
        };
      };
    };

    vpn-browser = {
      enable = true;
    };

    ddcutil = {
      enable = true;
      monitor = {
        enable = true;
        dataDir = ./monitor;
      };
    };

    bluetooth-resume = {
      enable = true;
    };
  };

  # PI WEB user services should survive logout/reboot.
  users.users.p.linger = true;

  # Battlemage + xe is currently stable on 6.12.74 here; newer 6.12.x regressed GPU init.
  boot.kernelPackages = pinnedKernelPkgs.linuxPackages;

  boot.kernelParams = [
    "usbcore.autosuspend=-1"
  ];

  zramSwap.enable = true;

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

  # Accept keep-awake lease requests from io's wake-proxy.
  services.wakeproxy.keepAwake = {
    maxDurationSeconds = 14400;
    sshTarget = {
      enable = true;
      authorizedKeysFile = config.my.secrets.getPath "wake-proxy-keep-awake-ssh" "public_key";
    };
  };

  services.avahi.enable = lib.mkForce false;
  services.resolved = {
    enable = true;
    settings.Resolve.MulticastDNS = "yes";
  };

  systemd.network.links."40-enp4s0" = {
    matchConfig.OriginalName = "enp4s0";
    linkConfig.WakeOnLan = "magic";
  };

  networking = {
    firewall.allowPing = true;
    # Allow localsend receive port
    # Allow 3000/1 and 5000/1 for dev server and tooling
    firewall.allowedTCPPorts = [53317 3001 5000 5001];
    # PI WEB for wakeproxy upstream (io only)
    firewall.extraInputRules =
      lib.mkAfter
      (config._module.args.mkRestrictedPortRules {
        port = 8504;
        allowedSources = ["10.0.0.1"];
      }).nft;
    firewall.extraCommands = lib.mkIf (!config.networking.nftables.enable) (lib.mkAfter
      (config._module.args.mkRestrictedPortRules {
        port = 8504;
        allowedSources = ["10.0.0.1"];
      }).iptables);
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Experimental = true;
        KernelExperimental = true;
        FastConnectable = true;
      };
      Policy = {
        AutoEnable = true;
      };
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

  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;

  programs.virt-manager.enable = true;

  systemd.services.nix-daemon.serviceConfig = {
    Nice = lib.mkForce 15;
    IOSchedulingClass = lib.mkForce "idle";
    IOSchedulingPriority = lib.mkForce 7;
    LimitNOFILE = "infinity";
  };

  # Cap the in-journal coredump backtrace size: a crashing QtWebEngine renderer
  # produced a >4M COREDUMP_STACK_TRACE entry that exceeds
  # systemd-journal-upload's per-entry buffer, making the uploader fail forever
  # on the same unskippable entry (NRestarts climbing). 512M keeps core dumps
  # but bounds the journal field so uploads can progress.
  systemd.coredump.settings.Coredump.ProcessSizeMax = "512M";
  users.users.p = {
    extraGroups = ["dialout"];
  };

  my.journalUpload.enable = true;
}
