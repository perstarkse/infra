{
  ctx,
  config,
  pkgs,
  ...
}: {
  # Workstation-only: agent forwarding lets the deploy/build host reuse the
  # interactive agent over SSH; servers must never enable it.
  clan.core.networking.forwardAgent = true;

  # electron 39.8.10 is EOL in nixpkgs 26.05; bitwarden-desktop pins to it.
  # Scoped here (and on ariel) instead of fleet-wide: servers never evaluate
  # electron, so the insecure-package allowance stays off there.
  nixpkgs.config.permittedInsecurePackages = [
    "electron-39.8.10"
  ];

  imports =
    [
      ./hardware.nix
      ./desktop.nix
      ./virtualisation.nix
      ./users/p.nix
      ./users/a.nix
      ./users/agent.nix
    ]
    ++ (with ctx.flake.nixosModules; [
      home-module
      sound
      options
      shared
      interception-tools
      blinkstick
      stylix
      niri
      terminal
      session-dispatch
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
      agent-ssh-access
      herdr-web-ui
      bambu-studio
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
      tether
    ])
    ++ (with ctx.inputs.varsHelper.nixosModules; [default])
    ++ (with ctx.inputs.privateInfra.nixosModules; [hello-service]);

  my = {
    # herdr-web-ui's bridge binds this host's LAN address (needs an inbound
    # firewall rule: see modules/system/herdr-web-ui.nix), not loopback.
    listenNetworkAddress = "10.0.0.15";

    gui.enable = true;

    stylix.enable = true;

    # Browser client for herdr: it is remote shell as `p`. The plugin's own
    # token gate (HERDR_WEB_TOKEN, exposed into the plugin's .env via
    # my.secrets below) is armed since 2026-10-13; there is still no nginx
    # auth in front of the LAN vhost.
    #
    # Retired 2026-10-11: the primary herdr.lan.stark.pub moved to makemake
    # (always on; charon sleeps). Republished same day under its own name so
    # charon's panes stay reachable directly: the bridge was never uninstalled
    # (still healthy on 10.0.0.15:7317), only unpublished. No remote-bundle
    # install needed — the UI's "add PC over SSH" path would deploy a second
    # bridge just to tunnel it back, which is redundant next to this vhost.
    # REVIEW-BY 2026-11-12: if makemake's UI reaches charon's panes through
    # the mesh (Add-PC or herdr machine list), retire this vhost entirely.
    herdr-web-ui = {
      enable = true;
      allowedFirewallSources = ["10.0.0.1"];
      endpoints = {
        enable = true;
        domain = "herdr-charon.lan.stark.pub";
        useWildcard = "lanstark";
        router = {
          enable = true;
          targets = ["io"];
        };
      };
    };

    docker.enable = true;
    fonts.enable = true;
    intel-gpu.enable = true;
    sound.enable = true;
    steam.enable = true;
    bambu-studio.enable = true;
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
      exposeUserSecrets = [
        {
          enable = true;
          secretName = "air-exhaust-mqtt";
          file = "charon-ro.env";
          user = config.my.mainUser.name;
          dest = "/home/${config.my.mainUser.name}/.config/air-exhaust/mqtt.env";
        }
        {
          # herdr mesh: `p`'s herdr reaches makemake's as `agent`, and the
          # fleet key is the only identity declaratively available here.
          enable = true;
          # The fleet key's private half, so the owner can `ssh agent@makemake`
          # from this account. 0400 p-owned: any coding agent running as `p`
          # can already become `agent` fleet-wide (roadmap accepted exposure),
          # so this grants the owner nothing the agents do not already have.
          secretName = "agent-ssh-key";
          file = "private_key";
          user = config.my.mainUser.name;
          dest = "/home/${config.my.mainUser.name}/.ssh/herdr-mesh_id_ed25519";
          mode = "0400";
        }
        {
          # Outbound half of agent@charon's own mesh: agent's herdr reaches
          # makemake as `agent`, and the mesh config above points at
          # ~/.ssh/id_ed25519 — which is where the hermes module would put it
          # on makemake, but hermes does not run on charon, so it lands here
          # directly instead. Same key, same 0400, other account.
          enable = true;
          secretName = "agent-ssh-key";
          file = "private_key";
          user = config.my.agent-ssh-access.user;
          dest = "/home/${config.my.agent-ssh-access.user}/.ssh/id_ed25519";
          mode = "0400";
        }
        {
          # Agent git auth key: account-level GitHub auth key
          # (write). User git over ssh to github.com only —
          # ~/.ssh/conf.d/github pins IdentitiesOnly so no other host ever
          # sees it.
          enable = true;
          secretName = "agent-git-auth";
          file = "private_key";
          user = config.my.agent-ssh-access.user;
          dest = "/home/${config.my.agent-ssh-access.user}/.ssh/git_auth_ed25519";
          mode = "0400";
        }
        {
          # herdr-web-ui token gate: HERDR_WEB_TOKEN into the plugin's .env
          # in p's config dir (charon's herdr runs as p). .env wins over
          # `env` (plugin 0.3.25+, included in the pinned checkout); with
          # the token set, every visitor needs it. Rotation: regenerate,
          # redeploy, restart herdr.
          enable = true;
          secretName = "herdr-web-ui";
          file = "plugin_env";
          user = config.my.mainUser.name;
          dest = "/home/${config.my.mainUser.name}/.config/herdr/plugins/config/devswha.herdr-web-ui/.env";
          mode = "0400";
        }
        {
          # Agent git signing key: signing-only. user.signingkey in the agent HM
          # block points at this file; the public half is registered on
          # GitHub (owner, browser step) and installed into /etc/ssh/allowed_signers.
          enable = true;
          secretName = "agent-git-sign";
          file = "private_key";
          user = config.my.agent-ssh-access.user;
          dest = "/home/${config.my.agent-ssh-access.user}/.ssh/git_sign_ed25519";
          mode = "0400";
        }
      ];
      discover = {
        enable = true;
        includeTags = ["aws" "charon" "openai" "openrouter" "context7" "user" "b2" "debug" "garage-s3" "wireguard-tunnels" "keep-awake" "attic-cache" "accounted-mcp" "digikey" "db-passwords" "journal-upload" "ntfy" "air-exhaust-mqtt" "agent-ssh-key" "agent-git" "herdr-web-ui"];
      };
      # Fail closed when an expected generator is absent after merge
      # (tag typo, missing includeTags). Static names only: dynamic
      # consumers (wireguard-tunnels-$name, restic-$job-$backend) are
      # covered by lib/secrets-discovery-check.py instead.
      requireGenerators = ["accounted-mcp-key" "agent-ssh-key" "agent-git-auth" "agent-git-sign" "attic-cache" "context7" "db-passwords" "digikey" "garage-s3" "herdr-web-ui" "journal-upload" "ntfy" "politikerstod-lekeberg" "politikerstod-orebro" "wake-proxy-keep-awake-ssh" "z-ai-env"];

      allowReadAccess = [
        {
          readers = [config.my.mainUser.name];
          path = config.my.secrets.getPath "z-ai-env" "env";
        }
        {
          # Agent MCP parity: agent's pi reads the same env via its own reader grant (the
          # !command pattern is unchanged — only the ACL differs).
          readers = [config.my.mainUser.name config.my.agent-ssh-access.user];
          path = config.my.secrets.getPath "accounted-mcp-key" "env";
        }
        {
          readers = [config.my.mainUser.name config.my.agent-ssh-access.user];
          path = config.my.secrets.getPath "context7" "env";
        }
        {
          # Granted because agent's digikey-mcp cannot start without the
          # client creds (digikey-mcp crashes at startup without them) —
          # required for the per-principal OAuth store separation (separate consent
          # flows per principal, never shared stores).
          # z-ai-env above stays p-only: provider LLM keys are not MCP creds.
          readers = [config.my.mainUser.name config.my.agent-ssh-access.user];
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

    atuin.enable = true;

    sccache-daemon = {
      enable = true;
      cacheDir = "/mnt/sdb/cache/sccache-daemon";
      cacheSize = "150G";
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

    tether = {
      enable = true;
      # WiFi pairing + clipboard + files + messages/notifications over BT.
      openFirewall = true;
      # bluetoothd --experimental so BlueZ exposes org.bluez.Bearer.LE1 before the
      # iPhone is paired: without it a bond has no LE half and ANCS notification
      # mirroring can never work (tether --bt-setup reports the step).
      experimentalBluetoothd = true;
    };

    journalUpload.enable = true;
  };

  # Accept keep-awake lease requests from io's wake-proxy.
  services.wakeproxy.keepAwake = {
    maxDurationSeconds = 14400;
    sshTarget = {
      enable = true;
      authorizedKeysFile = config.my.secrets.getPath "wake-proxy-keep-awake-ssh" "public_key";
    };
  };

  services.avahi.enable = true;
  # Tether's WiFi discovery (Bonjour) rides on avahi; resolved's mDNS responder
  # must stay off so the two don't fight over the .local domain. resolved keeps
  # handling unicast DNS.
  services.resolved.settings.Resolve.MulticastDNS = false;

  environment.systemPackages = with pkgs; [
    # On PATH system-wide so `ssh agent@charon 'herdr agent list'` resolves it:
    # a non-login ssh command gets sshd's default PATH, which does not include
    # the Nix profile or Home Manager's.
    ctx.inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default
    # herdr's antigravity-cli integration guards on `command -v python3` and
    # silently reports no session without it, while `herdr integration status`
    # only diffs the installed file and still says "current".
    python3
    unstable.code-cursor-fhs
    devenv
    localsend
    bluetuith
    discord
    ledger-live-desktop
    # PrismLauncher is Qt6: the global qt5ct platformtheme + kvantum style
    # override segfault it on startup (each var alone crashes, even --version).
    # Strip both; PrismLauncher falls back to Fusion + its builtin themes.
    (symlinkJoin {
      name = "prismlauncher-no-qt5ct";
      paths = [unstable.prismlauncher];
      buildInputs = [makeWrapper];
      postBuild = ''
        wrapProgram $out/bin/prismlauncher \
          --unset QT_STYLE_OVERRIDE \
          --unset QT_QPA_PLATFORMTHEME
      '';
    })
    gamescope
    bun
    google-cloud-sdk
  ];
}
