{
  ctx,
  config,
  lib,
  pkgs,
  ...
}: let
  agentUser = config.my.agent-ssh-access.user;
in {
  imports = with ctx.flake.nixosModules;
    [
      home-module
      ./hardware-configuration.nix
      ./boot.nix
      options
      shared
      interception-tools
      stylix
      docker
      attic-cache
      vaultwarden
      openwebui
      surrealdb
      minne-saas
      backups
      garage
      nous
      politikerstod
      atuin-server
      atuin
      webdav-htpasswd-secret
      webdav-garage

      paperless
      storage-alerts
      wireguard-tunnels
      indicator-alert-daemon
      supabase
      accounted
      accounted-ocr
      journal-upload
      agent-ssh-access
      hermes
      herdr-web-ui
      wake-charon
      signal-cli
    ]
    ++ (with ctx.inputs.varsHelper.nixosModules; [default])
    ++ (with ctx.inputs.privateInfra.nixosModules; [media mailserver]);

  # Home Manager profile for `agent`. This machine is the one that hosts the
  # agent toolchain (roadmap Phase B/C), and `agent` is the fleet's least
  # privileged account — no mainUser, no GUI, no sudo. Keep the import list to
  # what a non-interactive account actually needs: `options` carries the
  # my.secrets bridge into HM, `ssh` is the fleet access the toolchain needs,
  # `sops` comes along because Phase F hands pi an age key. Do NOT set
  # my.mainUser here — that is a different account on a different machine.
  home-manager.users.${config.my.agent-ssh-access.user} = {
    imports = with ctx.flake.homeModules;
      [
        options
        sops
        ssh
        herdr
        herdr-web-ui
        # pi shells out to `npm` by name at first run (extension installs
        # into ~/.pi/agent/npm). nodejs alone is not enough: the npm
        # wrapper ships in a separate output that bare `nodejs` does not
        # put on PATH. Charon gets this via my.node; agent gets it here.
        node
        git
        agentGit
        direnv
        zoxide
      ]
      ++ (with ctx.inputs.agentTooling.homeModules; [
        pi-agent
        antigravity
        shared-skills
        # Imported but NOT enabled, purely to declare my.agentTooling.pi-web.
        # agent-tooling's antigravity.nix guards its pi-web wiring with
        # `lib.attrByPath [... "pi-web" "enable"] false config` and comments that
        # the module "still evaluates" without it -- but attrByPath has to force
        # config.my.agentTooling.pi-web to discover it is absent, and forcing an
        # option nobody declared is an error, not a default. So the module is
        # only importable alongside pi-web. Costs nothing: all of pi-web.nix's
        # config sits behind `mkIf cfg.enable`, and this one stays off.
        pi-web
      ]);

    # The agent toolchain (roadmap Phase F). Both agents authenticate on their
    # first interactive run and headless runs reuse the cached credentials, so
    # there is deliberately NO secret here: no includeTags for provider keys, no
    # requireGenerators entries, no allowReadAccess grants. Nothing to rotate,
    # nothing that can leak into a backup.
    my.agentTooling = {
      pi-agent = {
        enable = true;
        # Panes are non-interactive. The permission extension asks questions and
        # nobody is there to answer, so an approval prompt is a hang. Disabled
        # rather than reconfigured: the boundary it enforces is `agent`'s, and
        # agent holds no sudo anywhere in the fleet.
        permissionSystem.enable = false;
        # Same MCP surface as charon's agent (owner decision 2026-10-13: git
        # identity + MCP parity). The digikey token store is agent's own —
        # per-principal stores, never shared (refresh rotation races).
        mcpServers = ctx.flake.lib.mkPiMcpServers {
          inherit config pkgs;
          inherit (ctx) inputs;
          tokenStore = "/home/agent/.local/state/digikey-mcp/tokens.json";
        };
      };
      antigravity.enable = true;
      shared-skills.enable = true;
    };

    # Same agent environment as charon (owner decision 2026-10-13). agentGit
    # gives signing + authorship + the github push stanza; the agent-git
    # vars (share = true, one keypair fleet-wide) deploy the private halves
    # via my.secrets.exposeUserSecrets below. my.git.enable sets the
    # committer identity — without it commits fall back to the system git
    # defaults and authorship/committer drift.
    my.git.enable = true;
    my.agentGit.enable = true;
    my.direnv.enable = true;
    my.zoxide.enable = true;

    # pi's first run shells out to `npm` by name (extension installs into
    # ~/.pi/agent/npm). nodejs arrives via the `node` homeModule import
    # above; this enables its global-prefix shim so npm resolves there too.
    my.node.enable = true;

    # The `pi` binary itself arrives through my.agentTooling.pi-agent.package,
    # which defaults to agent-tooling's packages.pi -- the same pi-coding-agent
    # pi-web bundles -- and lands on home.packages from the module. git and
    # ripgrep are the pane tools pi shells out to by name.
    home.packages = with pkgs; [
      git
      ripgrep
    ];

    # herdr runs as `agent` (the identity panes must be spawned as, and the
    # home the socket lands in).
    my.herdr = {
      enable = true;
      # No default in the HM module (home modules cannot see flake inputs), so
      # it comes from the locked input exactly as charon's does.
      package = ctx.inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
    };

    # Plugin half of the browser client. bindHost is NOT set: the HM module
    # already defaults it to my.listenNetworkAddress, and a loopback bind
    # would be unreachable from io's proxy.
    my.herdr-web-ui.enable = true;

    # The ssh client itself. `home.file.".ssh/conf.d/herdr-mesh"` below is
    # inert without it: nothing Includes conf.d/* until this module writes
    # ~/.ssh/config, and without that the outbound mesh fails with "Could not
    # resolve hostname charon" on first deploy. The ssh-agent user service it
    # also starts is harmless here (no keys are added to it; the fleet key is
    # used via IdentityFile).
    my.ssh.enable = true;

    # herdr mesh, makemake's half. charon's side reaches this one as `agent`
    # over plain ssh; the key it uses is the fleet key, installed into this
    # user's own ~/.ssh. known_hosts for charon comes from the same
    # installer that ships the key.
    home.file.".ssh/conf.d/herdr-mesh" = {
      text = ''
        Host charon 10.0.0.15
          HostName 10.0.0.15
          User agent
          IdentityFile ~/.ssh/id_ed25519
          IdentitiesOnly yes
          BatchMode yes
      '';
    };
  };

  # The io router DNAT-hijacks outbound :53 to its own resolver, which splits
  # mail.stark.pub -> 10.0.0.10 and caches NODATA for _acme-challenge.* per
  # stark.pub SOA (1800s). lego's DNS-01 propagation check therefore never sees
  # the freshly-created TXT within its 2m window and the nightly renewal fails.
  # Skip lego's own check and rely on Let's Encrypt validating against the real
  # authoritative NSs over the public internet.
  security.acme.certs."mail.stark.pub".extraLegoFlags = ["--dns.propagation-wait=120s"];

  # Clan-core's networking module sets systemd.network.wait-online.enable =
  # false (masking systemd-networkd-wait-online), so network-online.target
  # fired ~8s before enp1s0 got its DHCP lease and every unit gated on it (garage provisioners, restic garage bootstraps,
  # attic bootstrap) or binding 10.0.0.10 (nginx, atuin) failed on every boot.
  # Pin the wait to the primary NIC only: --operational-state=degraded is the
  # state the link reaches once its address is configured (same pattern as the
  # router's wait-online in modules/system/router/network.nix).
  systemd.network.wait-online = {
    enable = lib.mkForce true;
    timeout = 30;
    extraArgs = ["--interface=enp1s0" "--operational-state=degraded"];
  };

  # Git SSH allowed_signers for the agentGit module. Agent-line only: there
  # is no p account on this machine (mainUser.enable = false) and no p
  # public key declared, so there is no per@stark.pub principal to verify.
  # Skips silently on a fresh clone before `clan vars generate makemake`.
  systemd.services.install-agent-allowed-signers = {
    description = "Install git SSH allowed_signers (agent signing key)";
    after = ["local-fs.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
    };
    script = let
      signPub = config.my.secrets.getPath "agent-git-sign" "public_key";
    in ''
      set -euo pipefail
      if [ ! -s "${signPub}" ]; then
        echo "agent git signing public key not present yet; skipping allowed_signers install" >&2
        exit 0
      fi
      printf 'agent@stark.pub %s\n' "$(cat "${signPub}")" \
        | install -m 0444 -o root -g root /dev/stdin /etc/ssh/allowed_signers
    '';
  };

  my = {
    # Non-sudo fleet SSH for the personal agent. Unprivileged `agent` account,
    # `restrict`ed key, no wheel/docker/libvirtd, logs only.
    agent-ssh-access = {
      enable = true;
      # This machine hosts the agent toolchain, so unlike the rest of the fleet
      # `agent` needs a real HOME: Home Manager (Phase B) writes its whole
      # profile there and project checkouts go in ~/projects. createHome is safe
      # because the module closes the homedir authorized_keys path per-user
      # (see its `AuthorizedKeysFile` Match block). `home` is what drives
      # users.users.agent.home; do not also set that option directly.
      home = "/home/agent";
      createHome = true;
      # herdr's socket now lives in this user's own home, so no traverse ACLs
      # are needed. Writable scratch still comes from workDir.
      traversePaths = [];
    };

    # Magic-packet script for waking charon before driving it over SSH.
    # Runs on makemake (same broadcast reachability as io, one less hop).
    # Constants interpolate from services.wakeproxy option defaults, which
    # mirror io's values; makemake sets no services.wakeproxy itself.
    # keepAwake closes the Phase H gap: a direct WOL does not take
    # wakeproxy's keep-awake lease (only wake.stark.pub traffic does), so a
    # long agent run could hit charon's 1800s sleepInhibit ceiling. The
    # lease goes straight to charon's wakeproxy-keep-awake SSH target with
    # the wake-proxy-keep-awake-ssh key (read grant on `agent` below).
    wake-charon = {
      enable = true;
      keepAwake = {
        enable = true;
        identityFile = config.my.secrets.getPath "wake-proxy-keep-awake-ssh" "private_key";
      };
    };

    attic-cache.server = {
      enable = true;
      retentionPeriod = "1 months";
    };

    hermes = {
      enable = true;

      # IS the agent's home. Native mode sets HOME = stateDir, so this is what
      # makes the gateway an ordinary user of the machine. It must stay equal
      # to my.agent-ssh-access.home -- the module asserts the home's mode
      # against this value, and the fleet SSH key and known_hosts are installed
      # under it.
      stateDir = config.my.agent-ssh-access.home;

      mail.enable = true;

      customProvider = "commandcode";
      baseUrl = "https://api.commandcode.ai/provider/v1";
      # model = "meta/muse-spark-1.3-contributor";
      model = "stealth/space-bunny-alpha";
      modelProvider = "custom:commandcode";
      reasoningEffort = "high";

      # The credential is already in the env file as COMMANDCODE_API_KEY.
      credentialEnvVar = "COMMANDCODE_API_KEY";

      modelOverrides."custom:commandcode"."stealth/space-bunny-alpha" = {
        context_window = 1048576;
        supports_reasoning = true;
      };
    };

    signal-cli.enable = true;

    mainUser = {
      enable = false;
      name = "p";
    };

    # Browser client for herdr. Only io proxies here, so the bridge is
    # reachable from the router alone.
    #
    # THIS IS AN UNAUTHENTICATED REMOTE SHELL. The plugin's gate is off while
    # HERDR_WEB_TOKEN is unset and /api/health reports role "drive", so anyone
    # who can reach the vhost gets keystrokes into `agent`'s panes. LAN-only and
    # io-only bounds the exposure to "already on the LAN", which is not the
    # same as authentication.
    herdr-web-ui = {
      enable = true;
      allowedFirewallSources = ["10.0.0.1"];
      endpoints = {
        enable = true;
        domain = "herdr.lan.stark.pub";
        # No alias vhost for herdr-mk: the endpoint schema is one domain
        # per service, so the old name dies with the cutover. Bookmarks
        # get one edit; a second vhost doubles the unauthenticated
        # surface for a name nobody needs.
        useWildcard = "lanstark";
        router = {
          enable = true;
          targets = ["io"];
        };
      };
    };

    docker.enable = true;

    listenNetworkAddress = "10.0.0.10";

    backupFailureNtfy = {
      enable = true;
      url = "https://ntfy.lan.stark.pub/backup-alerts";
      tokenFile = config.my.secrets.getPath "ntfy" "backup-token";
    };

    privateInfra.overseerr.endpoints = {
      enable = true;
      domain = "request.stark.pub";
      public = true;
      cloudflareProxied = true;
      router = {
        enable = true;
        targets = ["io"];
      };
    };

    storage-alerts = {
      enable = true;
      mounts = [
        "/mnt/18tb"
        "/mnt/4tb"
        "/storage"
      ];
      mdadm.enable = true;
      ntfy = {
        serverUrl = "https://ntfy.lan.stark.pub";
        topic = "storage-alerts";
        tokenFile = config.my.secrets.getPath "ntfy" "storage-token";
        tags = ["warning" "floppy_disk" "makemake"];
      };
    };

    secrets = {
      discover = {
        enable = true;
        includeTags = ["makemake" "surrealdb" "b2" "minne-saas" "nous" "politikerstod" "politikerstod-lekeberg" "politikerstod-orebro" "garage" "garage-s3" "paperless" "ntfy" "attic-cache" "wireguard-tunnels" "supabase" "accounted" "journal-upload" "db-passwords" "heartbeat" "heartbeat-tls" "hermes" "hermes-mail" "agent-ssh-key" "agent-git" "accounted-mcp" "context7" "digikey" "keep-awake"];
      };
      # Fail closed when an expected generator is absent after merge
      # (tag typo, missing includeTags). Static names only: dynamic
      # consumers (wireguard-tunnels-$name, restic-$job-$backend) are
      # covered by lib/secrets-discovery-check.py instead.
      requireGenerators = ["accounted" "agent-ssh-key" "agent-git-auth" "agent-git-sign" "accounted-mcp-key" "attic-cache" "context7" "db-passwords" "digikey" "garage" "garage-s3" "heartbeat" "heartbeat-tls" "hermes-env" "hermes-mail" "journal-upload" "minne-saas" "nous" "ntfy" "politikerstod-lekeberg" "supabase" "surrealdb-credentials" "vaultwarden" "wake-proxy-keep-awake-ssh" "webdav-htpasswd"];

      allowReadAccess = [
        {
          # wake-charon lease: the agent SSHes charon's wakeproxy-keep-awake
          # forced-command target. Read-only ACL on the services-scope key
          # (0400 root:root + u:agent:r) — one line in this list is the whole
          # inventory entry (roadmap C6 rule).
          readers = ["agent"];
          path = config.my.secrets.getPath "wake-proxy-keep-awake-ssh" "private_key";
        }
        {
          readers = ["nous"];
          path = config.my.secrets.getPath "nous" "env";
        }
        {
          readers = ["politikerstod-lekeberg"];
          path = config.my.secrets.getPath "politikerstod-lekeberg" "env";
        }
        {
          readers = ["politikerstod-lekeberg"];
          path = config.my.secrets.getPath "db-passwords" "politikerstod";
        }
        {
          readers = ["paperless"];
          path = config.my.secrets.getPath "db-passwords" "paperless";
        }
        {
          readers = ["root"];
          path = config.my.secrets.getPath "db-passwords" "paperless.env";
        }
        {
          readers = ["root"];
          path = config.my.secrets.getPath "journal-upload" "client.key";
        }
        {
          readers = ["root"];
          path = config.my.secrets.getPath "journal-upload" "client.pem";
        }
        {
          readers = ["root"];
          path = config.my.secrets.getPath "journal-upload" "ca.pem";
        }
        {
          readers = ["root"];
          path = config.my.secrets.getPath "ntfy" "backup-token";
        }
        {
          readers = ["root"];
          path = config.my.secrets.getPath "ntfy" "indicator-token";
        }
        # C6 MCP parity: agent's pi reads the same env files as charon's
        # agent. p is NOT a reader here — makemake has no p account
        # (mainUser.enable = false), and a setfacl for a missing user fails
        # the activation. The vars themselves are shared (share = true), so
        # the same env content deploys on both machines.
        {
          readers = [agentUser];
          path = config.my.secrets.getPath "accounted-mcp-key" "env";
        }
        {
          readers = [agentUser];
          path = config.my.secrets.getPath "context7" "env";
        }
        {
          readers = [agentUser];
          path = config.my.secrets.getPath "digikey" "env";
        }
      ];

      exposeUserSecrets = [
        {
          # Decision C2: account-level GitHub auth key (write). Same keypair
          # fleet-wide (share = true generators): no per-machine GitHub
          # registration.
          enable = true;
          secretName = "agent-git-auth";
          file = "private_key";
          user = agentUser;
          dest = "/home/${agentUser}/.ssh/git_auth_ed25519";
          mode = "0400";
        }
        {
          # Decision C1: signing-only key; user.signingkey (agentGit module)
          # points at this file, and install-agent-allowed-signers below
          # installs the public half into /etc/ssh/allowed_signers.
          enable = true;
          secretName = "agent-git-sign";
          file = "private_key";
          user = agentUser;
          dest = "/home/${agentUser}/.ssh/git_sign_ed25519";
          mode = "0400";
        }
      ];
    };

    # Backups configuration
    backups = let
      mkB2 = path: {
        enable = true;
        inherit path;
        frequency = "daily";
        backend = {
          type = "b2";
          bucket = null;
          lifecycleKeepPriorVersionsDays = 30;
        };
      };
    in {
      accounted = mkB2 config.my.accounted.dataDir;
      minne-saas = mkB2 config.my.minne-saas.dataDir;
      vaultwarden = mkB2 config.my.vaultwarden.backupDir;

      # RocksDB file-level backup: surreal export over ws is unsupported on this arch.
      surrealdb = mkB2 config.my.surrealdb.dataDir;
      surrealdb-saas = mkB2 config.my.minne-saas.surrealdb.dataDir;

      nous =
        (mkB2 config.my.nous.dataDir)
        // {
          # The pg_dump artifact lives inside the restic data dir and MUST be
          # snapshotted: it is the only DB coverage this job has. Prepare runs
          # to completion before restic scans (same unit, no mid-write race),
          # and restic dedups an unchanged dump to ~0 bytes per snapshot.
          backupPrepareCommand = ''
            ${pkgs.sudo}/bin/sudo -u nous \
              ${pkgs.postgresql}/bin/pg_dump -Fc -f ${config.my.nous.dataDir}/nous_prod.dump nous_prod
          '';
          backupCleanupCommand = ''
            rm -f ${config.my.nous.dataDir}/nous_prod.dump
          '';
        };

      openwebui =
        (mkB2 config.my.openwebui.dataDir)
        // {
          # Most of the dataDir is cache/ (HuggingFace model weights + ephemeral
          # generations) — regenerable, worthless in a backup. User state is
          # webui.db + vector_db + uploads (~200M).
          exclude = ["${config.my.openwebui.dataDir}/cache"];
        };

      # Personal agent state: sessions, session DB, memory, skills, cron store,
      # mcp-tokens, config.yaml, workspace. One directory, one job — the agent
      # writes nothing durable outside it (see modules/system/hermes.nix).
      # Scoped to HERMES_HOME and the workspace, NOT the whole stateDir: since
      # Phase D the stateDir IS /home/agent, so backing it up wholesale would
      # sweep ~/.pi, ~/.cache and every other cache into the repo on top of
      # what the gateway actually owns.
      hermes =
        (mkB2 "${config.my.hermes.stateDir}/.hermes")
        // {
          # The session DB is SQLite and live-written: a raw restic copy of a
          # torn database is worse than no copy. Snapshot a consistent .backup
          # first, inside the snapshotted path — same shape as the pg_dump
          # prep this block already does for nous, paperless and politikerstod.
          #
          # The [ -f ] guard is load-bearing: `sqlite3 missing.db ".backup ..."`
          # exits 0 and CREATES the source file, so without it a restic run
          # before the agent's first launch would leave a 0-byte root-owned
          # state.db that hermes (running as its own user) cannot then open.
          backupPrepareCommand = ''
            if [ -f ${config.my.hermes.stateDir}/.hermes/state.db ]; then
              install -d -m 0700 ${config.my.hermes.stateDir}/.hermes/.restic-prep
              ${pkgs.sqlite}/bin/sqlite3 ${config.my.hermes.stateDir}/.hermes/state.db \
                ".backup '${config.my.hermes.stateDir}/.hermes/.restic-prep/state.db'"
            fi
          '';
          backupCleanupCommand = "rm -rf ${config.my.hermes.stateDir}/.hermes/.restic-prep";
          # $HERMES_HOME/.env is regenerated from the hermes-env generator on
          # every activation: the generator is the source of truth, so keys
          # never enter a backup repo. Same for the installed himalaya
          # config.toml (re-installed from hermes-mail on activation AND on
          # rotation — a backup copy would hold live IMAP passwords).
          #
          # The LIVE .hermes/state.db* is deliberately NOT excluded: it may be
          # torn, but .restic-prep/state.db in the same snapshot is the
          # consistent copy, and a restore that only recovered the prep would
          # lose every session taken before the first restic run. If a restore
          # ever reports a corrupt state.db, replace it with the .restic-prep
          # copy from the same snapshot.
          # The himalaya config.toml no longer needs excluding: it lives at
          # ~/.config/himalaya/config.toml, outside HERMES_HOME, so it is not in
          # this snapshot at all.
          exclude = ["${config.my.hermes.stateDir}/.hermes/.env"];
        };

      hermes-workspace = (mkB2 "${config.my.hermes.stateDir}/workspace") // {};

      paperless = {
        enable = true;
        path = config.my.paperless.dataDir;
        frequency = "daily";
        # Documents are the most irreplaceable data on this box; keep a copy
        # in Garage (same-house replication) and offsite on B2.
        backends = {
          garage = {
            type = "garage-s3";
          };
          b2 = {
            type = "b2";
            lifecycleKeepPriorVersionsDays = 30;
          };
        };
        restore.backend = "garage";
        # The pg_dump artifact lives inside the restic data dir and MUST be
        # snapshotted: it is the only DB coverage this job has. Prepare runs
        # to completion before restic scans (same unit, no mid-write race),
        # and restic dedups an unchanged dump to ~0 bytes per snapshot.
        backupPrepareCommand = ''
          PGPASSWORD=$(cat ${config.my.secrets.getPath "db-passwords" "paperless"}) \
          ${pkgs.postgresql}/bin/pg_dump \
            -h 192.168.100.22 -U paperless -Fc -f ${config.my.paperless.dataDir}/paperless.dump paperless
        '';
        backupCleanupCommand = ''
          rm -f ${config.my.paperless.dataDir}/paperless.dump
        '';
      };

      politikerstod-lekeberg =
        (mkB2 config.my.politikerstod.instances.lekeberg.dataDir)
        // {
          # The pg_dump artifact lives inside the restic data dir and MUST be
          # snapshotted: it is the only DB coverage this job has. Prepare runs
          # to completion before restic scans (same unit, no mid-write race),
          # and restic dedups an unchanged dump to ~0 bytes per snapshot.
          backupPrepareCommand = ''
            PGPASSWORD=$(cat ${config.my.secrets.getPath "db-passwords" "politikerstod"}) \
              ${pkgs.postgresql}/bin/pg_dump \
              -h 192.168.100.12 -U politikerstod -Fc \
              -f ${config.my.politikerstod.instances.lekeberg.dataDir}/politikerstod.dump \
              politikerstod_prod
          '';
          backupCleanupCommand = ''
            rm -f ${config.my.politikerstod.instances.lekeberg.dataDir}/politikerstod.dump
          '';
          exclude = [
            "${config.my.politikerstod.instances.lekeberg.dataDir}/fastembed_cache"
          ];
        };
    };

    vaultwarden = {
      enable = true;
      endpoints = {
        enable = true;
        domain = "vault.lan.stark.pub";
        useWildcard = "lanstark";
        lanOnly = true;
        router = {
          enable = true;
          targets = ["io"];
        };
      };
    };

    openwebui = {
      enable = true;
      port = 8080;
      dataDir = "/storage/.state/openwebui";
      # Digest-pinned image: autoUpdate's `podman pull <sha256>` is a no-op,
      # yet the timer would restart the container weekly for zero change.
      # Bump the digest explicitly to update.
      image = "ghcr.io/open-webui/open-webui@sha256:6a773e5c3a246b65cbe74ce942b294292c0e5f81c138f703d111bc162f7d7c3d";
      autoUpdate = false;
      endpoints = {
        enable = true;
        domain = "chat.stark.pub";
        lanOnly = true;
        router = {
          enable = true;
          targets = ["io"];
        };
      };
    };

    # SurrealDB configuration
    surrealdb = {
      enable = true;
    };

    # Minne SaaS configuration
    minne-saas = {
      enable = true;
      port = 3001;

      demoMode = true;
      demoAllowedMutatingPaths = [
        "/signin"
        "/gdpr/accept"
        "/gdpr/deny"
        "/waitlist"
        "/waitlist/"
      ];
      endpoints = {
        enable = true;
        domain = "minne.stark.pub";
        demoDomain = "minne-demo.stark.pub";
        public = true;
        cloudflareProxied = true;
        router = {
          enable = true;
          targets = ["io"];
        };
      };
    };

    # Garage S3-compatible storage (clustered with io)
    garage = {
      enable = true;
      metaDir = "/var/lib/garage/meta";
      replicationMode = 2;
      rpcPublicAddr = "10.0.0.10:3901";
      bindAddress = "10.0.0.10";
      zone = "makemake";
    };

    # WebDAV access to Garage S3 for iPhone
    webdav-garage = {
      enable = true;
      bucket = "shared";
      endpoint = "http://10.0.0.10:3900";
      bindAddress = "10.0.0.10";
      port = 8081;
      htpasswdFile = config.my.secrets.getPath "webdav-htpasswd" "htpasswd";
      endpoints = {
        enable = true;
        domain = "webdav.lan.stark.pub";
        useWildcard = "lanstark";
        basicAuthSecret = {
          realm = "WebDAV";
          name = "webdav-htpasswd";
          file = "htpasswd";
        };
        router = {
          enable = true;
          targets = ["io"];
        };
      };
    };

    # Restrict WebDAV to the router's nginx only (io proxies
    # webdav.lan.stark.pub → 10.0.0.10:8081). The endpoints module emits the
    # dual-backend firewall rules (nft extraInputRules + iptables
    # extraCommands) and excludes 8081 from allowedTCPPorts.
    endpoints.services.webdav-garage.firewall.local.allowedSources = ["10.0.0.1"];

    # Nous burnout prevention app
    nous = {
      enable = true;
      # Garage S3 binds the host LAN IP (no localhost listener).
      s3.endpoint = "http://10.0.0.10:3900";
      endpoints = {
        enable = true;
        public = true;
        domain = "nous.fyi";
        cloudflareProxied = true;
        router = {
          enable = true;
          targets = ["io"];
        };
      };

      database = {
        name = "nous_prod";
        user = "nous";
      };
    };

    # Politikerstöd Service Instances
    politikerstod = {
      instances = {
        lekeberg = {
          enable = true;
          port = 5150;
          host = "https://politikerstod.stark.pub";
          openFirewall = true;
          endpoints = {
            enable = true;
            domain = "politikerstod.stark.pub";
            public = true;
            cloudflareProxied = true;
            router = {
              enable = true;
              targets = ["io"];
            };
          };

          database = {
            name = "politikerstod_prod";
            user = "politikerstod";
            host = "192.168.100.12"; # Container IP
            port = 5432;
            enableContainer = true;
            allowedHosts = ["10.0.0.15"]; # charon - remote worker
            passwordFile = config.my.secrets.getPath "db-passwords" "politikerstod";
            container = {
              name = "politikerstod-db"; # Preserve existing container data
              hostAddress = "192.168.100.10";
              localAddress = "192.168.100.12";
            };
          };

          scraper.baseUrl = "https://meetings.lekeberg.se";
          s3.bucket = "politikerstod";
          s3.prefix = "lekeberg";
          s3.endpoint = "http://10.0.0.10:3900";

          settings = {
            logLevel = "info";
            prettyBacktrace = true;
            numWorkers = 4;
            pollingHistoricalMonths = 36;
            authAllowedEmailDomains = ["lekeberg.se"];
          };
        };

        orebro = {
          enable = false;
          port = 5151;
          host = "https://orebro.politikerstod.stark.pub";
          openFirewall = true;
          endpoints = {
            enable = true;
            domain = "orebro.politikerstod.stark.pub";
            public = true;
            cloudflareProxied = true;
            router = {
              enable = true;
              targets = ["io"];
            };
          };

          database = {
            name = "politikerstod_orebro";
            user = "politikerstod_orebro";
            host = "192.168.100.13"; # Container IP
            port = 5432;
            enableContainer = true;
            proxyPort = 5433;
            allowedHosts = ["10.0.0.15"]; # charon - remote worker
            container = {
              hostAddress = "192.168.100.11";
              localAddress = "192.168.100.13";
            };
          };

          scraper.baseUrl = "https://politiskamoten.regionorebrolan.se/";
          s3.prefix = "orebro";

          settings = {
            logLevel = "info";
            prettyBacktrace = true;
            numWorkers = 4;
            pollingHistoricalMonths = 1;
          };
        };
      };
    };

    # Atuin Sync Server
    atuin-server = {
      enable = true;
      port = 8888;
      openFirewall = true;
      endpoints = {
        enable = true;
        domain = "atuin.lan.stark.pub";
        useWildcard = "lanstark";
        router = {
          enable = true;
          targets = ["io"];
        };
      };
    };

    # Atuin client
    atuin.enable = true;

    # Paperless-ngx document management
    paperless = {
      enable = true;
      openFirewall = true;
      port = 28981;
      address = "10.0.0.10";
      url = "https://dokument.lan.stark.pub";
      dataDir = "/var/lib/paperless";
      consumptionDir = "/var/lib/paperless/consume";
      mediaDir = "/var/lib/paperless/media";
      ocr = {
        language = "swe+eng";
        # paperless 2.20 dropped the legacy "always" value; "force" keeps
        # the same intent (OCR everything, never skip).
        mode = "force";
      };
      database = {
        name = "paperless";
        user = "paperless";
        host = "192.168.100.22";
        port = 5432;
        enableContainer = true;
        passwordFile = config.my.secrets.getPath "db-passwords" "paperless";
        passwordEnvFile = config.my.secrets.getPath "db-passwords" "paperless.env";
        container = {
          hostAddress = "192.168.100.20";
          localAddress = "192.168.100.22";
        };
      };
      tika.enable = true;
      endpoints = {
        enable = true;
        domain = "dokument.lan.stark.pub";
        useWildcard = "lanstark";
        router = {
          enable = true;
          targets = ["io"];
        };
      };
      s3Consumption = {
        enable = true;
        bucket = "paperless-consume";
        endpoint = "http://10.0.0.10:3900";
        region = "garage";
      };
    };

    wireguard-tunnels = {
      enable = true;
      tunnels = {
        genome-worktree-zenith = {
          activationPolicy = "manual";
        };
      };
    };

    # Self-hosted Supabase + Accounted (LAN-only via io)
    supabase = {
      enable = true;
      additionalRedirectUrls = [
        "https://accounting.lan.stark.pub/auth/callback"
        "https://accounting.lan.stark.pub/api/auth/callback"
      ];
      endpoints = {
        enable = true;
        domain = "supabase.lan.stark.pub";
        useWildcard = "lanstark";
        lanOnly = true;
        router = {
          enable = true;
          targets = ["io"];
        };
      };
    };

    accounted = {
      enable = true;
      supabaseUrl = "https://supabase.lan.stark.pub";
      endpoints = {
        enable = true;
        domain = "accounting.lan.stark.pub";
        useWildcard = "lanstark";
        lanOnly = true;
        # Next.js auth sends large Set-Cookie headers; increase nginx proxy
        # buffers to avoid "upstream sent too big header" 502 errors.
        extraConfig = ''
          proxy_buffer_size 16k;
          proxy_buffers 8 16k;
          proxy_busy_buffers_size 32k;
        '';
        router = {
          enable = true;
          targets = ["io"];
        };
      };
      # Public Resend webhook for the invoice-inbox extension; the 444 gating
      # and upstream live in the accounted module, io imports the endpoint.
      invoiceWebhook = {
        enable = true;
        domain = "invoices.stark.pub";
        public = true;
        router = {
          enable = true;
          targets = ["io"];
        };
      };
    };

    accounted-ocr = {
      enable = true;
    };
  };

  # No `SetEnv` for the herdr socket any more. The server is now a user unit
  # owned by `agent` itself (roadmap Phase C), so a client in `agent`'s own
  # session resolves $HOME/.config/herdr on its own — which is exactly what the
  # old block was working around. The PATH half of the problem is solved at
  # environment.systemPackages above instead of per-session SetEnv.

  services.indicator-alert-daemon = {
    enable = true;
    intervalType = "1wk";
    pollFrequency = 86400;
    tickers = [
      {
        symbol = "ETH-USD";
        intervalType = "1d";
        indicators = [
          {
            type = "rsi";
            threshold = 30.0;
            period = 14;
          }
          {
            type = "rsi";
            threshold = 70.0;
            period = 14;
            direction = "above";
          }
        ];
      }
      {
        symbol = "BOTZ";
        indicators = [
          {
            type = "rsi";
            threshold = 30.0;
            period = 14;
          }
          {
            type = "rsi";
            threshold = 70.0;
            period = 14;
            direction = "above";
          }
        ];
      }
      {
        symbol = "SEKEUR=X";
        indicators = [
          {
            type = "rsi";
            threshold = 30.0;
            period = 14;
          }
          {
            type = "rsi";
            threshold = 70.0;
            period = 14;
            direction = "above";
          }
        ];
      }
    ];
  };

  services.deleterr.enable = true;

  services.paperless.settings = {
    # Consume dir is an rclone/FUSE mount from Garage S3; use polling instead of inotify.
    PAPERLESS_CONSUMER_POLLING = 30;
    PAPERLESS_CONSUMER_RECURSIVE = true;
  };

  environment.systemPackages = with pkgs; [
    mergerfs
    unrar
    # On PATH system-wide so `ssh agent@makemake 'herdr agent list'` resolves it:
    # a non-login ssh command gets sshd's default PATH, which has neither the
    # Nix profile nor Home Manager's. This is what keeps the inbound half of
    # the mesh alive now that the server is a user unit (roadmap Phase C
    # side-effect 2). python3 for the same reason charon carries it: herdr's
    # antigravity-cli integration guards on `command -v python3` and reports no
    # session without it, while `herdr integration status` still says current.
    ctx.inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default
    python3
  ];

  programs.fuse.userAllowOther = true;

  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      function unrar-dirs --description "Unrar files in specified directories"
        for dir in $argv
          if test -d "$dir"
            echo "Processing $dir..."
            pushd "$dir"
            if test (count (find . -maxdepth 1 -name "*.rar")) -gt 0
              ${pkgs.unrar}/bin/unrar e -o+ *.rar
            else
              echo "No rar files found in $dir"
            end
            popd
          else
            echo "Directory $dir does not exist"
          end
        end
      end
    '';
  };

  # Centralized logging to router for fail2ban
  # Mail brute-force protection: SMTP/IMAP terminate on makemake, so the
  # postfix/dovecot jails run here against the local journal (the router's
  # copies of these jails read forwarded remote journals and never fire).
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "30m";
    ignoreIP = [
      "127.0.0.0/8"
      "::1"
      # Fleet peers must never be banned. 2026-10-11: charon (10.0.0.15)
      # ate a 30m sshd ban from my own `ssh agent@makemake.lan` attempts
      # with the wrong local key — every LAN host refused, not just SSH —
      # and the mesh died with it. fail2ban's stock iptables action drops
      # all traffic from the banned IP, not just port 22.
      "10.0.0.1"
      "10.0.0.10"
      "10.0.0.15"
    ];
    jails = {
      postfix = {
        settings = {
          enabled = true;
          filter = "postfix";
          backend = "systemd";
          journalmatch = "_SYSTEMD_UNIT=postfix.service";
          maxretry = 5;
          findtime = "10m";
          bantime = "30m";
        };
      };
      dovecot = {
        settings = {
          enabled = true;
          filter = "dovecot";
          backend = "systemd";
          journalmatch = "_SYSTEMD_UNIT=dovecot.service";
          maxretry = 5;
          findtime = "10m";
          bantime = "30m";
        };
      };
    };
  };

  # dovecot 2.3 logs via journald as "imap-login: Login aborted: ... (auth failed,
  # N attempts ...) ... rip=<HOST>", which the stock fail2ban dovecot filter
  # (written for the syslog form) does not match.
  environment.etc."fail2ban/filter.d/dovecot.local".text = ''
    [Definition]
    failregex = \(auth failed, [0-9]+ attempts in [0-9]+ secs\).*rip=<HOST>
    ignoreregex =
  '';

  # Centralized logging to router for fail2ban — mTLS with the router's
  # journal-remote listener (client cert signed by journal-upload ca.pem).
  my.journalUpload.enable = true;

  # indicator-alert-daemon publishes to a write-protected ntfy topic; the app
  # has no auth support, so wrap its config: ntfy accepts the token in the
  # ?auth= query param as base64url("Bearer <token>"), resolved at runtime from
  # the secret (never baked into the store).
  systemd.services.indicator-alert-daemon = let
    iad = config.services.indicator-alert-daemon;
    iadFmt = pkgs.formats.json {};
    iadToken = config.my.secrets.getPath "ntfy" "indicator-token";
    iadBin = ctx.inputs.indicator-alert-daemon.packages.${pkgs.system}.default;
    iadConfig = iadFmt.generate "indicator-alert-daemon.json" (
      {
        ntfy_url = "https://ntfy.lan.stark.pub/indicator-alerts";
        interval_type = iad.intervalType;
        frequency_seconds = iad.pollFrequency;
        ticker_delay_ms = iad.tickerDelayMs;
        tickers = map (t:
          {
            inherit (t) symbol indicators;
          }
          // lib.optionalAttrs (t.intervalType != null) {interval_type = t.intervalType;})
        iad.tickers;
      }
      // lib.optionalAttrs (iad.dbPath != null) {db_path = iad.dbPath;}
    );
  in {
    serviceConfig = {
      ExecStart = lib.mkForce (pkgs.writeShellScript "indicator-alert-daemon-tokenized" ''
        set -euo pipefail
        token=$(cat ${iadToken})
        auth=$(printf 'Bearer %s' "$token" | ${pkgs.coreutils}/bin/base64 | ${pkgs.coreutils}/bin/tr '+/' '-_' | ${pkgs.coreutils}/bin/tr -d '=\n')
        # StateDirectory is writable under ProtectSystem=strict (/run is not)
        ${pkgs.jq}/bin/jq --arg u "https://ntfy.lan.stark.pub/indicator-alerts?auth=$auth" '.ntfy_url = $u' ${iadConfig} > /var/lib/indicator-alert-daemon/config.json
        exec ${iadBin}/bin/indicator-alert-daemon --config /var/lib/indicator-alert-daemon/config.json
      '');
      DynamicUser = lib.mkForce false;
    };
  };

  # The daemon reads the ntfy token only at startup: restart it when the
  # token file actually changes on disk (restartTriggers on /run/secrets
  # paths are inert strings that never fire — see mosquitto.nix).
  systemd.paths.indicator-token-rotation = {
    description = "Restart indicator-alert-daemon when its ntfy token rotates";
    wantedBy = ["multi-user.target"];
    pathConfig = {
      PathChanged = [(config.my.secrets.getPath "ntfy" "indicator-token")];
      Unit = "indicator-token-rotation-restart.service";
    };
  };

  systemd.services.indicator-token-rotation-restart = {
    description = "Restart indicator-alert-daemon after token rotation";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl try-restart indicator-alert-daemon.service";
    };
  };
}
