{
  ctx,
  config,
  pkgs,
  lib,
  ...
}: {
  # PI WEB user services should survive logout/reboot.
  users.users.p.linger = true;

  home-manager.users.${config.my.mainUser.name} = {
    imports = with ctx.flake.homeModules;
      [
        options
        sops
        herdr-web-ui
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
      sleepInhibit.enable = true;
    };

    my.herdr-web-ui.enable = true;

    # C4: ~/projects is the post-rename front door to the shared tree.
    # mkOutOfStoreSymlink would be the idiom, but `config` here is the NixOS
    # module's config — the HM profile's config.lib is unreachable from a
    # home-manager.users attrset — so inline the same construction (a store
    # symlink pointing at the absolute path; HM links the home name to it).
    # ~/repos (a manual symlink made 2025-06) stays as the compat link
    # through the cooling period. REMOVE-BY 2026-11-12: delete this comment
    # block and any surviving ~/repos symlink once nothing references it
    # (pi session cwds, direnv allow-files, shell muscle memory).
    home.file."projects".source =
      pkgs.runCommandLocal "projects-out-of-store" {}
      "ln -s /mnt/sdb/repos $out";

    # herdr mesh: charon's herdr reaches makemake's as `agent` over SSH. The
    # IdentityFile is the fleet key, exposed to `p` by my.secrets below — `p`'s
    # own ~/.ssh/id_ed25519 is Home Manager-generated, so its public half is not
    # a secret and cannot be authorized on makemake.
    home.file.".ssh/conf.d/herdr-mesh" = {
      text = ''
        Host makemake 10.0.0.10
          HostName 10.0.0.10
          User agent
          IdentityFile ~/.ssh/herdr-mesh_id_ed25519
          IdentitiesOnly yes
          BatchMode yes
      '';
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
          # same trust level. ~/repos and ~/projects are symlinks to this
          # mount and are matched via canonical path resolution; ~/repos is
          # the pre-rename compat link, drop once cooling period ends (REMOVE-BY 2026-11-12,
          # after 2026-10-12). Full map (replaces the module default).
          permissions.external_directory = {
            "*" = "ask";
            "/mnt/sdb/repos/*" = "allow";
            "~/repos/*" = "allow";
            "~/projects/*" = "allow";
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
          mcpServers = ctx.flake.lib.mkPiMcpServers {
            inherit config pkgs;
            inherit (ctx) inputs;
            tokenStore = "/home/p/.local/state/digikey-mcp/tokens.json";
          };
        };
        # RETIRED 2026-10-13: pi-web was wakeproxy's upstream; the public door
        # now proxies makemake's herdr-web-ui instead (io: upstreamHost
        # 10.0.0.10:7317). The pi-web module import stays above because
        # antigravity can only eval alongside it; the service is off and
        # /home/p/.pi-web state is inert.
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
}
