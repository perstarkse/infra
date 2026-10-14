{
  ctx,
  config,
  ...
}: let
  agentUser = config.my.agent-ssh-access.user;
in {
  imports =
    (with ctx.flake.nixosModules; [
      home-module
      ./hardware-configuration.nix
      ./boot.nix
      ./storage.nix
      ./services.nix
      ./users/agent.nix

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
    ])
    ++ (with ctx.inputs.varsHelper.nixosModules; [default])
    ++ (with ctx.inputs.privateInfra.nixosModules; [media mailserver]);

  my = {
    mainUser = {
      enable = false;
      name = "p";
    };

    docker.enable = true;

    listenNetworkAddress = "10.0.0.10";

    atuin.enable = true;

    # Centralized logging to router for fail2ban — mTLS with the router's
    # journal-remote listener (client cert signed by journal-upload ca.pem).
    journalUpload.enable = true;

    wireguard-tunnels = {
      enable = true;
      tunnels = {
        genome-worktree-zenith = {
          activationPolicy = "manual";
        };
      };
    };

    secrets = {
      discover = {
        enable = true;
        includeTags = ["makemake" "surrealdb" "b2" "minne-saas" "nous" "politikerstod" "politikerstod-lekeberg" "politikerstod-orebro" "garage" "garage-s3" "paperless" "ntfy" "attic-cache" "wireguard-tunnels" "supabase" "accounted" "journal-upload" "db-passwords" "heartbeat" "heartbeat-tls" "hermes" "hermes-mail" "agent-ssh-key" "agent-git" "accounted-mcp" "context7" "digikey" "keep-awake" "herdr-web-ui"];
      };
      # Fail closed when an expected generator is absent after merge
      # (tag typo, missing includeTags). Static names only: dynamic
      # consumers (wireguard-tunnels-$name, restic-$job-$backend) are
      # covered by lib/secrets-discovery-check.py instead.
      requireGenerators = ["accounted" "agent-ssh-key" "agent-git-auth" "agent-git-sign" "accounted-mcp-key" "attic-cache" "context7" "db-passwords" "digikey" "garage" "garage-s3" "heartbeat" "heartbeat-tls" "hermes-env" "hermes-mail" "herdr-web-ui" "journal-upload" "minne-saas" "nous" "ntfy" "politikerstod-lekeberg" "supabase" "surrealdb-credentials" "vaultwarden" "wake-proxy-keep-awake-ssh" "webdav-htpasswd"];

      allowReadAccess = [
        {
          # wake-charon lease: the agent SSHes charon's wakeproxy-keep-awake
          # forced-command target. Read-only ACL on the services-scope key
          # (0400 root:root + u:agent:r) — one line in this list is the whole
          # inventory entry: every credential the agent can read is declared in Nix.
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
        # Agent MCP parity: agent's pi reads the same env files as charon's
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
          # Agent git auth key: account-level GitHub auth key (write). Same keypair
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
          # Agent git signing key: signing-only; user.signingkey
          # (agentGit module) points at this file, and
          # install-agent-allowed-signers below installs the public half into
          # /etc/ssh/allowed_signers.
          enable = true;
          secretName = "agent-git-sign";
          file = "private_key";
          user = agentUser;
          dest = "/home/${agentUser}/.ssh/git_sign_ed25519";
          mode = "0400";
        }
        {
          # herdr-web-ui token gate: HERDR_WEB_TOKEN lands straight into the
          # plugin's config dir as .env (KEY=value; .env wins over `env`,
          # supported since plugin 0.3.25, which the pin includes). With the
          # token set, every visitor — wakeproxy's proxied vhost included —
          # needs it; pairing a device bypasses it only for that device.
          # Rotation: regenerate the generator, redeploy, restart herdr (the
          # bridge reads the token once at start).
          enable = true;
          secretName = "herdr-web-ui";
          file = "plugin_env";
          user = agentUser;
          dest = "/home/${agentUser}/.config/herdr/plugins/config/devswha.herdr-web-ui/.env";
          mode = "0400";
        }
      ];
    };
  };
}
