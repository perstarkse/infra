# herdr-web-ui (Home Manager half): install the devswha/herdr-web-ui plugin and
# give herdr.service the toolchain its [[startup]] hook needs.
#
# Split from modules/system/herdr-web-ui.nix, which publishes the endpoint:
# herdr.service is a user unit and `my.herdr` is a Home Manager option, so this
# half belongs under modules/home/ like every other user-scope module.
#
# LIMIT: `herdr plugin install` resolves the plugin at HEAD of its GitHub repo
# unless pluginRepo names a tag, and it builds against the network (bun install).
# The install oneshot is idempotent in effect but not in content. Pin pluginRepo
# to a tag once this stops being a prototype.
{
  config.flake.homeModules.herdr-web-ui = {
    config,
    lib,
    osConfig,
    pkgs,
    ...
  }: let
    cfg = config.my.herdr-web-ui;
    herdrBin = lib.getExe config.my.herdr.package;

    # Bound in the let, not as a derivation sibling: Nix attrset siblings are
    # not in lexical scope of each other, so `version` would be invisible inside
    # the nested `src` and `meta` attrsets below.
    bunVersion = "1.4.2";

    bun = pkgs.stdenv.mkDerivation {
      pname = "bun";
      version = bunVersion;
      src = pkgs.fetchurl {
        url = "https://github.com/oven-sh/bun/releases/download/bun-v${bunVersion}/bun-linux-x64.zip";
        hash = "sha256-NjaPrvdSeHXV/6UuU81IAhdB8qg+tiCKjdZAaNQiqRM=";
      };
      nativeBuildInputs = [pkgs.unzip];
      dontStrip = true;
      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin
        # stdenv sets sourceRoot to the archive's single top-level directory,
        # so the build runs inside bun-linux-x64/ already.
        cp bun $out/bin/bun
        runHook postInstall
      '';
      meta = {
        description = "Bun ${bunVersion}, pinned for herdr-web-ui's >=1.4 build floor";
        # The pinned source is the x64 release only; do not claim aarch64.
        platforms = ["x86_64-linux"];
      };
    };

    # The system directories stay. Setting PATH on a unit REPLACES systemd's
    # default (/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin),
    # so a bare lib.makeBinPath here silently removes every basic tool from the
    # server and from every pane it spawns. Only the two nix dirs need adding.
    pluginPath = "${lib.makeBinPath [bun pkgs.nodejs_22]}:/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin";

    installScript = pkgs.writeShellScript "herdr-web-ui-install" ''
      set -euo pipefail
      # Pinned by ref, not floating on HEAD. A newer HEAD (e6febbe) ignores
      # HOST and binds loopback only, while 9153e60b (what charon runs, health
      # 200 on its LAN IP) honours it. The installer reinstalls when the
      # installed ref drifts from the configured one; `plugin install` does not
      # overwrite, so a drifting install is uninstalled first.
      installed_ref=$(${herdrBin} plugin list 2>/dev/null | grep herdr-web-ui | grep -o "@[0-9a-f]*" | head -1 || true)
      want_ref="@${cfg.pluginRef}"
      if [ "$installed_ref" = "$want_ref" ]; then
        echo "herdr-web-ui: already at $want_ref"
        exit 0
      fi
      if [ -n "$installed_ref" ]; then
        echo "herdr-web-ui: installed $installed_ref drifts from $want_ref; reinstalling"
        ${herdrBin} plugin uninstall devswha.herdr-web-ui || true
      fi
      ${herdrBin} plugin install --yes --ref ${cfg.pluginRef} ${cfg.pluginRepo}
    '';
  in {
    options.my.herdr-web-ui = {
      enable = lib.mkEnableOption "herdr-web-ui Home Manager side (plugin install)";

      pluginRepo = lib.mkOption {
        type = lib.types.str;
        default = "devswha/herdr-web-ui";
        description = "GitHub repo passed to `herdr plugin install`.";
      };

      pluginRef = lib.mkOption {
        type = lib.types.str;
        default = "9153e60b53abe7e65420c8c8036928d41998e1df";
        description = ''
          Git ref passed as `herdr plugin install --ref`. Pinned, not HEAD:
          HEAD moves and has broken HOST binding before. This is the rev
          running on charon (health 200 on its LAN IP).
        '';
      };

      bindHost = lib.mkOption {
        type = lib.types.str;
        # Read from the OS side rather than repeated per machine:
        # server/index.ts binds process.env.HOST, defaulting to 127.0.0.1, and
        # a loopback-only bridge is unreachable from the reverse proxy. A
        # `tailscale serve` deployment wants loopback and overrides this.
        default = osConfig.my.listenNetworkAddress;
        description = ''
          Address the plugin's bridge binds. Must be reachable from whatever
          reverse proxies to it; 127.0.0.1 only suits a same-host proxy or
          `tailscale serve`.
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      # bun goes in home.packages rather than into the herdr unit's PATH:
      # setting PATH on the unit REPLACES the inherited one, and panes
      # spawned by the server then lose ~/.nix-profile/bin (agy, zoxide,
      # cargo gone inside panes, fine in a normal terminal). The manager's
      # PATH already carries ~/.nix-profile/bin, so this satisfies the
      # plugin's [[startup]] hook without touching PATH at all.
      home.packages = [bun];

      # HOST reaches the `bun scripts/plugin.ts start` startup hook THROUGH
      # herdr (the hook reads process.env, defaulting to 127.0.0.1), so it
      # must be on the server's own environment — there is no other channel.
      systemd.user.services.herdr.Service.Environment = ["HOST=${cfg.bindHost}"];

      # Belt and suspenders: the [[startup]] hook is one-shot per herdr start,
      # so a bridge that bound 127.0.0.1 before HOST was set survives every
      # redeploy (the start script sees a live port and leaves it alone).
      # Writing HOST into the plugin's own `env` file makes the value stick
      # regardless of hook timing. `env` is read BEFORE `.env`, which stays
      # the owner's for the token and PORT; activation only fills in a missing
      # HOST so a hand-set one is never clobbered.
      home.activation.herdrWebUiHost = lib.hm.dag.entryAfter ["writeBoundary"] ''
        cfgDir="$HOME/.config/herdr/plugins/config/devswha.herdr-web-ui"
        if [ ! -e "$cfgDir/env" ] || ! grep -q '^HOST=' "$cfgDir/env" 2>/dev/null; then
          run mkdir -p "$cfgDir"
          run sh -c "printf 'HOST=${cfg.bindHost}\\n' >> \"$cfgDir/env\""
        fi
      '';

      systemd.user.services.herdr-web-ui-install = {
        Unit = {
          Description = "Install the herdr-web-ui plugin";
          After = ["herdr.service"];
        };
        Service = {
          Type = "oneshot";
          # One network build, and deliberately no Restart: a boot loop when
          # GitHub is unreachable helps nobody.
          RemainAfterExit = true;
          TimeoutStartSec = "20min";
          Environment = [
            "PATH=${pluginPath}"
            "HERDR_SOCKET_PATH=${config.my.herdr.socketDir}/herdr.sock"
          ];
          ExecStart = "${installScript}";
        };
        Install.WantedBy = ["default.target"];
      };

      # Restart the bridge when its env file changes. The bridge reads its
      # environment ONCE at process start and SURVIVES herdr restarts (the
      # [[startup]] hook sees a live port and leaves it alone), so a token
      # that lands after the bridge — first deploy (exposeUserSecrets runs in
      # the system manager, racing the user manager's herdr start) or a
      # rotation — would stay unarmed forever: verified live on makemake
      # 2026-10-14, bridge from Oct 13 with "via":"open" while the Oct 14
      # .env sat unread next to it, and every API route but /api/health hung.
      # PathChanged fires on creation too, so the first deploy is covered;
      # identical-content redeploys are cmp-protected no-ops and stay quiet.
      # The start command self-guards ("already running for this checkout and
      # port"), so a redundant trigger is harmless. HOME-relative: works in
      # any herdr-owner profile (agent on makemake, p on charon).
      systemd.user.paths.herdr-web-ui-env = {
        Install.WantedBy = ["default.target"];
        pathConfig.PathChanged = "${config.xdg.configHome}/herdr/plugins/config/devswha.herdr-web-ui/.env";
      };
      systemd.user.services.herdr-web-ui-env-restart = {
        Unit.Description = "Restart the herdr-web-ui bridge after its env file changed";
        Service = {
          Type = "oneshot";
          TimeoutStartSec = "5min";
          Environment = ["PATH=${pluginPath}"];
          ExecStart = pkgs.writeShellScript "herdr-web-ui-env-restart" ''
            set -eu
            # Patterns chosen so they cannot match this script's own cmdline.
            pkill -f 'herdr-web-ui-.*server/managed\.ts' 2>/dev/null || true
            pkill -f 'herdr-web-ui/updates/.*server/supervisor\.ts' 2>/dev/null || true
            pkill -f 'bun server/index\.ts' 2>/dev/null || true
            sleep 1
            checkout=$(ls -d "$HOME"/.config/herdr/plugins/github/devswha.herdr-web-ui-* 2>/dev/null | head -1)
            if [ -z "$checkout" ]; then
              echo "herdr-web-ui: no plugin checkout yet; nothing to restart" >&2
              exit 0
            fi
            cd "$checkout"
            log="''${XDG_STATE_HOME:-$HOME/.local/state}/herdr/plugins/devswha.herdr-web-ui/server.log"
            mkdir -p "$(dirname "$log")"
            setsid nohup ${bun}/bin/bun scripts/plugin.ts start >> "$log" 2>&1 < /dev/null &
          '';
        };
      };
    };
  };
}
