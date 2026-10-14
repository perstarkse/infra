{
  ctx,
  config,
  pkgs,
  ...
}: let
  agentUser = config.my.agent-ssh-access.user;
in {
  # Home Manager profile for `agent`. This machine is the one that hosts the
  # agent toolchain (roadmap Phase B/C), and `agent` is the fleet's least
  # privileged account — no mainUser, no GUI, no sudo.
  home-manager.users.${agentUser} = {
    imports = with ctx.flake.homeModules; [
      agentProfile
      herdr-web-ui
    ];

    my.agentProfile.enable = true;
    my.herdr-web-ui.enable = true;
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
      gitSigning.enable = true;
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

    # Browser client for herdr. Only io proxies here, so the bridge is
    # reachable from the router alone.
    #
    # TWO auth layers since the wakeproxy cutover (2026-10-13): io's
    # wakeproxy password-gates the public vhost (wake.stark.pub → this
    # bridge), and HERDR_WEB_TOKEN — exposed into the plugin's .env via
    # my.secrets above — gates every visitor of the bridge itself, LAN
    # included. Until both deploy, the LAN vhost is still an
    # unauthenticated remote shell into `agent`'s panes.
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
  };

  environment.systemPackages = with pkgs; [
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
}
