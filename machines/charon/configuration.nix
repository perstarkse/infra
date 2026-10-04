{
  ctx,
  config,
  pkgs,
  lib,
  ...
}: let
  secondUser = "a";

  # The `agent` account herdr's socket is shared with (see my.herdr.shareWith).
  agentUser = config.my.agent-ssh-access.user;

  # Socket the herdr server binds and every client resolves. Duplicated from the
  # Home Manager module's my.herdr.socketDir default ($HOME/.config/herdr)
  # because sshd config is system-level and cannot read the HM options. Keep the
  # two in step: changing my.herdr.socketDir means changing this too.
  herdrSocket = "/home/${config.my.mainUser.name}/.config/herdr/herdr.sock";

  # GDM's switch-user entry point, used to hand the box over without ending the
  # running session. gdm-50.1 common/gdm-common.c: gdm_goto_login_session →
  # create_transient_display → this method (daemon/gdm-local-display-factory.xml).
  switchUserToGreeter = pkgs.writeShellApplication {
    name = "switch-user-greeter";
    text = ''
      exec ${lib.getExe' pkgs.glib "gdbus"} call --system \
        --dest org.gnome.DisplayManager \
        --object-path /org/gnome/DisplayManager/LocalDisplayFactory \
        --method org.gnome.DisplayManager.LocalDisplayFactory.CreateTransientDisplay
    '';
  };

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
  # Workstation-only: agent forwarding lets the deploy/build host reuse the
  # interactive agent over SSH; servers must never enable it.
  clan.core.networking.forwardAgent = true;

  # electron 39.8.10 is EOL in nixpkgs 26.05; bitwarden-desktop pins to it.
  # Scoped here (and on ariel) instead of fleet-wide: servers never evaluate
  # electron, so the insecure-package allowance stays off there.
  nixpkgs.config.permittedInsecurePackages = [
    "electron-39.8.10"
  ];

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
        hermes-inspect
        niri
        node
        voxtype
        wtp
        local-ai
        swayidle
        wow-launcher
        tether
        herdr
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
        antigravity
      ]);

    my.herdr = {
      enable = true;
      package = ctx.inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
      # Share the server with the fleet's non-sudo `agent` account: Hermes on
      # makemake drives charon's agents over plain ssh as `agent`, and herdr
      # hardcodes its sockets to 0600. The server stays owned by `p` — panes
      # spawn as the server user, and ~/.pi/agent is 0700 p, so an agent-owned
      # server would come up with an empty agent config.
      shareWith = [agentUser];
    };

    home.packages = [
      pkgs.agent-browser
      pkgs.gh
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
      hermes-inspect.enable = true;
      local-ai.enable = true;
      ncspot.enable = true;
      nix-scaffold.enable = true;
      node.enable = true;
      sccache = {
        enable = true;
        cacheDir = "/mnt/sdb/cache/sccache-daemon";
        cacheSize = "150G";
      };
      ssh.enable = true;
      starship.enable = true;
      voxtype.enable = true;
      xdg-mimeapps.enable = true;
      xdg-userdirs.enable = true;
      zellij.enable = true;
      zoxide.enable = true;
      wow-launcher.enable = true;
      tether.enable = true;

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
        airExhaust.enable = true;
      };

      agentTooling = {
        pi-agent = {
          enable = true;
          ponytail.enable = true;
          permissionSystem.enable = false;
          governance = {
            enable = true;
            # Nightly zero-token digest of cross-project traces + permission
            # friction; report lands in ~/.local/state/agent-governance/.
            digest.enable = true;
          };
          # Machine-specific CWD-boundary allow: all agent work lives under
          # /mnt/sdb/repos (25 project session dirs, ~56k governance entries);
          # cross-project reads are constant and every sibling repo is the
          # same trust level. ~/repos is a symlink to this mount and is
          # matched via canonical path resolution. Full map (replaces the
          # module default for this option).
          permissions.external_directory = {
            "*" = "ask";
            "/mnt/sdb/repos/*" = "allow";
            "~/repos/*" = "allow";
            "~/.cargo/registry/*" = "allow";
            "~/.cargo/git/*" = "allow";
            "~/.cache/nix/*" = "allow";
            "~/.local/share/nix/*" = "allow";
            "/nix/store/*" = "allow";
            "/tmp/*" = "allow";
          };
          shellAlias = "PI_FFF_MODE=override command pi";
          defaultProvider = "commandcode";
          defaultModel = "meta/muse-spark-1.3-contributor";
          extraPackages = [];
          models = {};
          subagentOverrides = lib.genAttrs ["scout" "context-builder" "planner" "researcher" "reviewer" "delegate"] (_: {
            model = "commandcode/meta/muse-spark-1.3-contributor";
            thinking = "high";
            fallbackModels = [];
            defaultContext = "fresh";
            systemPromptMode = "append";
            systemPrompt = "You are a fresh subagent with zero inherited context. Your only knowledge comes from the task message and the tools you use. Gather all necessary context yourself. Do not assume prior knowledge.";
          });
          mcpServers = {
            accounted = {
              url = "https://accounting.lan.stark.pub/api/extensions/ext/mcp-server/mcp?client=pi-code";
              # pi's built-in MCP support has no `bearerToken` field: the
              # Authorization header is a `!command` value, and that command must
              # be the WHOLE value (pi runs it through a shell and takes trimmed
              # stdout), so the Bearer prefix comes from the command itself.
              headers.Authorization = "!cat ${config.my.secrets.getPath "accounted-mcp-key" "env"} | grep '^ACCOUNTED_MCP_API_KEY=' | cut -d= -f2 | sed 's/^/Bearer /'";
            };
            context7 = {
              url = "https://mcp.context7.com/mcp";
              headers = {
                CONTEXT7_API_KEY = "!cat ${config.my.secrets.getPath "context7" "env"} | grep '^CONTEXT7_API_KEY=' | cut -d= -f2";
              };
            };
            digikey = {
              # MyLists tools need the app subscribed to MyLists in the portal and its
              # OAuth Callback URL set to DIGIKEY_CALLBACK_URL below; the account owner
              # then runs the one-time mylists_authorize consent flow.
              command = "${ctx.inputs.digikeyMcp.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/digikey-mcp";
              env = {
                DIGIKEY_CLIENT_ID = "!cat ${config.my.secrets.getPath "digikey" "env"} | grep '^DIGIKEY_CLIENT_ID=' | cut -d= -f2";
                DIGIKEY_CLIENT_SECRET = "!cat ${config.my.secrets.getPath "digikey" "env"} | grep '^DIGIKEY_CLIENT_SECRET=' | cut -d= -f2";
                DIGIKEY_CALLBACK_URL = "https://localhost:8139/digikey_callback";
                DIGIKEY_TOKEN_STORE = "/home/p/.local/state/digikey-mcp/tokens.json";
              };
            };
            # agentcad: stdio MCP server exposing the CAD CLI as typed tools
            # (venv interpreter from the shared agent-tooling package).
            agentcad = {
              command = "${ctx.inputs.agentTooling.packages.${pkgs.stdenv.hostPlatform.system}.agentcad}/bin/python";
              args = ["-m" "agentcad.mcp"];
              # Host workaround: OCP's GL renderer aborts the process with an
              # X error on a live display it cannot use (BadWindow kills the
              # auto-diff PNG phase — agentcad 0.4.0 has no --no-diff). An
              # unreachable DISPLAY fails the GL phase gracefully instead.
              # See printing/desktop-side-box/spec.md → CAD tooling.
              env = {
                DISPLAY = "invalid-display";
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
        antigravity = {
          enable = true;
          # allowedCommands: the shared module default already covers
          # git/nix/cargo/just plus read-only inspection tools; override here
          # only to add machine-specific extras.
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

  # Second account: GNOME on the same seat. The list is deliberately short —
  # the modules the main account needs for a tiled, terminal-driven desktop
  # (niri config, noctalia, rofi, qutebrowser, local-ai, agent tooling) either do
  # nothing in a GNOME session or fight it. Not importing the niri home module
  # is also what keeps its niri config and the 4s niri IPC wait out of her
  # activation, since that module gates on the system-wide my.gui.session
  # rather than anything per user. No `sops`/`mail-clients` either: those carry
  # an age keyFile at /home/<user>/.config/sops/age/keys.txt and she has no
  # fleet secrets to decrypt.
  home-manager.users.${secondUser} = {lib, ...}: {
    imports = with ctx.flake.homeModules; [
      fish
      starship
      kitty
      xdg-userdirs
      xdg-mimeapps
      firefox
      chromium
      mail
      bitwarden-client
      ssh
    ];

    my = {
      programs.mail = {
        enable = true;
        clients = ["thunderbird"];
      };
      bitwarden-client.enable = true;
      chromium.enable = true;
      firefox.enable = true;
      fish.enable = true;
      starship.enable = true;
      ssh.enable = true;
      xdg-mimeapps.enable = true;
      xdg-userdirs.enable = true;
    };

    # The main account's lock is a Noctalia keybinding, not an idle trigger.
    # GNOME's automatic-lock defaults have moved between releases, so both keys
    # are set rather than inherited: without this her session stays unlocked
    # whenever she steps away from a seat the other account is using.
    # idle-delay stays at the schema default (300s) and lock-delay at 0.
    # Swedish session: GNOME input source plus LANG. System glibc already
    # ships sv_SE (in supportedLocales via the shared en_US/sv_SE extras),
    # so only the session default changes; the main account keeps en_US.
    home.language.base = "sv_SE.UTF-8";

    # Daily user-flatpak updates: Flathub ships its own CVE fixes outside
    # the NixOS rebuild cycle, so this must not wait for a deploy.
    systemd.user.services.flatpak-user-update = {
      Unit.Description = "Update user Flatpaks";
      Service = {
        Type = "oneshot";
        ExecStart = "/run/current-system/sw/bin/flatpak update --noninteractive --assumeyes";
      };
    };
    systemd.user.timers.flatpak-user-update = {
      Unit.Description = "Daily user Flatpak updates";
      Timer = {
        OnCalendar = "daily";
        Persistent = true;
      };
      Install.WantedBy = ["timers.target"];
    };

    dconf.settings = {
      "org/gnome/desktop/input-sources" = {
        sources = [(lib.hm.gvariant.mkTuple ["xkb" "se"])];
      };
      "org/gnome/desktop/screensaver" = {
        idle-activation-enabled = true;
        lock-enabled = true;
      };
    };
  };

  my = {
    stylix.enable = true;

    # Non-sudo fleet SSH for the personal agent. Unprivileged `agent` account,
    # `restrict`ed key, no wheel/docker/libvirtd, logs only.
    #
    # /home/p is 0700, so without these ACLs the agent cannot reach the repos
    # at all. --x on the home (traverse only, cannot list it) plus r-x on the
    # repos themselves: the agent can read and clone infra/homelab without
    # gaining any visibility into the rest of the home directory.
    agent-ssh-access = {
      enable = true;
      traversePaths = ["/home/p"];
      readablePaths = ["/home/p/repos"];
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
      ];
      discover = {
        enable = true;
        includeTags = ["aws" "charon" "openai" "openrouter" "context7" "user" "b2" "debug" "garage-s3" "wireguard-tunnels" "keep-awake" "attic-cache" "accounted-mcp" "digikey" "db-passwords" "journal-upload" "ntfy" "air-exhaust-mqtt" "agent-ssh-key"];
      };
      # Fail closed when an expected generator is absent after merge
      # (tag typo, missing includeTags). Static names only: dynamic
      # consumers (wireguard-tunnels-$name, restic-$job-$backend) are
      # covered by lib/secrets-discovery-check.py instead.
      requireGenerators = ["accounted-mcp-key" "agent-ssh-key" "attic-cache" "context7" "db-passwords" "digikey" "garage-s3" "journal-upload" "ntfy" "politikerstod-lekeberg" "politikerstod-orebro" "wake-proxy-keep-awake-ssh" "z-ai-env"];

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

    # One greeter session name, per-user desktop behind it: GDM's
    # defaultSession is applied to *every* account (see session-dispatch.nix).
    sessionDispatch = {
      enable = true;
      users.${secondUser} = "gnome";
    };

    gui = {
      enable = true;
    };

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
  };

  # PI WEB user services should survive logout/reboot.
  users.users.p.linger = true;

  # Flatpak escape hatch for the second account: she gets GNOME Software
  # (the "app store") with Flathub, user-scope installs so no wheel/sudo is
  # needed. The system base stays declarative; her day-to-day apps go here.
  # enabling flatpak also pulls gnome-software via the gnome module.
  services.flatpak.enable = true;

  # Flathub remote, system scope so every account (including non-wheel ones
  # installing --user) resolves it. No declarative option exists upstream,
  # so one idempotent oneshot.
  systemd.services.flatpak-add-flathub = {
    description = "Add Flathub remote (system)";
    wantedBy = ["multi-user.target"];
    wants = ["network-online.target"];
    after = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.flatpak}/bin/flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo";
    };
  };

  # Swedish layout at the greeter too: GDM inherits the system XKB setting,
  # so Swedish characters work in the password field before any session (and
  # its dconf below) loads. The niri session sets its own layout and is
  # unaffected; only the console keymap follows along.
  services.xserver.xkb.layout = "se";

  # GDM replaced greetd here: greetd runs one greeter session at a time, so
  # handing the machine to the second account meant logging out and losing the
  # running session. GDM can start an extra greeter on a spare VT and keep both
  # sessions alive (logind hands the single DRM master to whichever one is on
  # the active VT). Consequence: her GNOME session lives on its own VT and
  # this niri session stays on the first one.
  services.displayManager = {
    gdm.enable = true;
    # Replaces greetd's initial_session autologin.
    autoLogin = {
      enable = true;
      user = config.my.mainUser.name;
    };
  };

  # Second desktop. Its own mkDefault services (GNOME Online Accounts,
  # evolution-data-server, power-profiles-daemon, tracker indexer) are all
  # defaults, so none of them collide with the networkd setup in shared.nix.
  services.desktopManager.gnome.enable = true;

  # The account, its groups and its password come from the `user-a`
  # clan users service instance (flake/parts/clan.nix). Only the uid is set
  # here, so the account is a fixed 1001 like the main account's 1000.
  users.users.${secondUser}.uid = 1001;

  # CreateTransientDisplay is auth_admin for every caller class
  # (gdm-50.1 data/org.gnome.displaymanager.policy), which would mean a polkit
  # agent plus a password prompt from inside a bare niri session. The main
  # account is admin on its own machine and the action only starts a greeter —
  # the second user still authenticates to log in. `active` keeps it to a
  # session that actually holds the seat.
  security.polkit.extraConfig = ''
    polkit.addRule(function (action, subject) {
      if (action.id !== "org.gnome.displaymanager.displayfactory.manage-user-displays") {
        return undefined;
      }
      if (subject.local && subject.active && subject.user === "${config.my.mainUser.name}") {
        return "yes";
      }
      return undefined;
    });
  '';

  # Battlemage + xe is currently stable on 6.12.74 here; newer 6.12.x regressed GPU init.
  boot.kernelPackages = pinnedKernelPkgs.linuxPackages;

  boot.kernelParams = [
    "usbcore.autosuspend=-1"
  ];

  zramSwap = {
    enable = true;
    priority = 100;
  };

  swapDevices = [
    {
      device = "/mnt/sdb/swap/swapfile";
      size = 64 * 1024; # 64G overflow on enterprise SATA (INTEL SSDSC2KB038TZ) below zram
      priority = 10;
    }
  ];

  # sda (/mnt/sdb) enters standby on its own (~42x this boot, 3-4s per wake)
  # and on every suspend (STANDBY IMMEDIATE even times out after 5s). The
  # swapfile (2+GB used, priority 10 above zram) lives there, so the first
  # post-resume page faults stall with the display already shown — the
  # few-seconds resume freeze. Disable the internal standby timer (-S 0) and
  # APM spindown (-B 255); the resume hook re-applies it since the drive
  # resets to defaults on power cycle.
  # ponytail: drive standby off, not ALPM tuning; revisit if power draw matters.
  systemd.services.sda-disable-standby = {
    description = "Disable sda internal standby (swap lives on /mnt/sdb)";
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.hdparm}/sbin/hdparm -S 0 -B 255 /dev/disk/by-id/ata-INTEL_SSDSC2KB038TZ_PHYI329101K03P8EGN";
    };
  };
  powerManagement.resumeCommands = "${pkgs.hdparm}/sbin/hdparm -S 0 -B 255 /dev/disk/by-id/ata-INTEL_SSDSC2KB038TZ_PHYI329101K03P8EGN || true";

  boot.loader.systemd-boot.configurationLimit = 5;

  services.journald.extraConfig = ''
    SystemMaxUse=1G
    SystemMaxFileSize=100M
    MaxRetentionSec=14day
    RuntimeMaxUse=250M
  '';

  nix.settings.auto-optimise-store = true;

  # Native SATA offload (no bind mounts) — keep NVMe for /nix/store + rust-analyzer salsa DB
  # Docker high churn -> enterprise SATA endurance; huggingface/pip sequential -> SATA
  virtualisation.docker.daemon.settings."data-root" = "/mnt/sdb/cache/docker";

  environment.sessionVariables = {
    HF_HOME = "/mnt/sdb/cache/home-p/huggingface";
    PIP_CACHE_DIR = "/mnt/sdb/cache/home-p/pip";
  };

  systemd.tmpfiles.rules = [
    "d /mnt/sdb/cache 0755 root root -"
    "d /mnt/sdb/cache/docker 0711 root root -"
    "d /mnt/sdb/cache/home-p 0755 p users -"
    "d /mnt/sdb/cache/home-p/huggingface 0755 p users -"
    "d /mnt/sdb/cache/home-p/pip 0755 p users -"
    "d /mnt/sdb/swap 0755 root root -"
  ];

  nix.gc.options = lib.mkForce "--delete-older-than 7d";

  # Decode and persist machine-check exceptions (MCEs) so hardware errors like the
  # uncorrectable EX watchdog errors before the Aug 19 hard reset are not lost.
  # Records go to /var/lib/rasdaemon/ras-mc_event.db; query with ras-mc-ctl.
  hardware.rasdaemon.enable = true;

  environment.systemPackages = with pkgs; [
    # On PATH system-wide so `ssh agent@charon 'herdr agent list'` resolves it:
    # a non-login ssh command gets sshd's default PATH, which does not include
    # the Nix profile or Home Manager's.
    ctx.inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default
    switchUserToGreeter
    unstable.code-cursor-fhs
    devenv
    localsend
    bluetuith
    discord
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
    virt-manager
    gamescope
    bun
    google-cloud-sdk
  ];

  # pi-agent-browser-native probes the managed-session policy lock owner's
  # process start time via ps at the hardcoded paths /bin/ps then /usr/bin/ps
  # (dist/extensions/agent-browser/lib/process-identity.js). NixOS has neither
  # directory, so pi's agent_browser tool fails with "Managed-session policy
  # coordination is unavailable or busy". Symlink /bin/ps onto procps so the
  # deterministic lock path works without relying on PATH.
  # The herdr server runs as `p` (its panes spawn pi/agy and need `p`'s
  # 0700 ~/.pi/agent), and its socket is shared with `agent` via ACL — see
  # modules/home/herdr.nix. `agent` still has no way to FIND that socket on its
  # own: its HOME is /var/empty/agent, so herdr would resolve a different path.
  # SetEnv hands it the real one for every session, which is what makes
  # `ssh agent@charon 'herdr agent list'` work with no wrapper on the makemake
  # side. PATH likewise: sshd's default PATH has no /run/current-system/sw.
  services.openssh.extraConfig = lib.mkAfter ''
    Match User ${agentUser}
        SetEnv HERDR_SOCKET_PATH=${herdrSocket} PATH=/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin
  '';

  system.activationScripts.agent-browser-ps = ''
    mkdir -p /bin
    ln -sfn ${pkgs.procps}/bin/ps /bin/ps
  '';

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

  my.tether = {
    enable = true;
    # WiFi pairing + clipboard + files + messages/notifications over BT.
    openFirewall = true;
    # bluetoothd --experimental so BlueZ exposes org.bluez.Bearer.LE1 before the
    # iPhone is paired: without it a bond has no LE half and ANCS notification
    # mirroring can never work (tether --bt-setup reports the step).
    experimentalBluetoothd = true;
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
    extraGroups = ["dialout" "plugdev"];
  };
  users.groups.plugdev = {};

  services.udev.extraRules = lib.mkAfter ''
    SUBSYSTEM=="usb", ATTR{idVendor}=="0d28", MODE="0664", GROUP="plugdev", TAG+="uaccess"
    KERNEL=="hidraw*", ATTRS{idVendor}=="0d28", MODE="0666", TAG+="uaccess"
    SUBSYSTEM=="tty", ATTRS{idVendor}=="0d28", MODE="0666", TAG+="uaccess"
  '';

  my.journalUpload.enable = true;
}
