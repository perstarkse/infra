{
  config.flake.homeModules.wow-launcher = {
    pkgs,
    lib,
    config,
    ...
  }: let
    cfg = config.my.wow-launcher;

    protonPath = "${pkgs.unstable.proton-ge-bin.steamcompattool}";
    umuRun = lib.getExe pkgs.umu-launcher;

    wowLauncher = pkgs.writeShellApplication {
      name = "wow-launcher";
      runtimeInputs = [pkgs.umu-launcher pkgs.procps];
      text = ''
        set -euo pipefail

        compatdata="''${WOW_COMPATDATA:-$HOME/.local/share/Steam/steamapps/compatdata/${cfg.compatdataAppId}}"
        wineprefix="$compatdata/pfx"
        bnet_exe="$wineprefix/drive_c/Program Files (x86)/Battle.net/${cfg.battleNetExe}"

        usage() {
          cat <<'EOF'
        Usage: wow-launcher [battlenet|kill|help]

          battlenet  Launch Battle.net in the Steam Proton prefix (default)
          kill       Stop Battle.net / WoW / wineserver (useful after suspend)
          help       Show this help

        Environment:
          WOW_COMPATDATA     Override Steam compatdata dir (default ends with ${cfg.compatdataAppId})
          WOW_BNET_WINED3D   Set to 1 if Battle.net CEF login UI freezes (can break Play→game)
        EOF
        }

        require_prefix() {
          if [[ ! -d "$wineprefix" ]]; then
            echo "error: Wine prefix not found: $wineprefix" >&2
            echo "hint: install Battle.net/WoW via Steam first, or set WOW_COMPATDATA" >&2
            exit 1
          fi
        }

        setup_common_env() {
          export WINEPREFIX="$wineprefix"
          export STEAM_COMPAT_DATA_PATH="$compatdata"
          export STEAM_COMPAT_CLIENT_INSTALL_PATH="''${STEAM_COMPAT_CLIENT_INSTALL_PATH:-$HOME/.local/share/Steam}"
          export PROTONPATH="${protonPath}"
          # umu-battlenet enables protonfixes; GAMEID=0 + PROTONFIXES_DISABLE broke Play→exe spawn
          export GAMEID="umu-battlenet"
          export WINE_SIMULATE_WRITECOPY=1
          export WINEDLLOVERRIDES="''${WINEDLLOVERRIDES:+$WINEDLLOVERRIDES;}locationapi=d"
        }

        cmd_battlenet() {
          require_prefix
          if [[ ! -f "$bnet_exe" ]]; then
            echo "error: Battle.net exe not found: $bnet_exe" >&2
            exit 1
          fi
          setup_common_env
          # WINED3D helps blank CEF login, but Play inherits it and then fails to spawn WoW.
          # Opt in only when needed: WOW_BNET_WINED3D=1
          if [[ "''${WOW_BNET_WINED3D:-0}" == "1" ]]; then
            export PROTON_USE_WINED3D=1
          fi
          exec ${umuRun} "$bnet_exe" "$@"
        }

        cmd_kill() {
          pkill -f -i 'Battle\.net' 2>/dev/null || true
          pkill -f -i 'WowClassic\.exe' 2>/dev/null || true
          pkill -f -i 'Agent\.exe' 2>/dev/null || true
          pkill -f 'wineserver' 2>/dev/null || true
          echo "stopped Battle.net / WoW / wineserver (if any were running)"
        }

        cmd="''${1:-battlenet}"
        if [[ $# -gt 0 ]]; then
          shift
        fi

        case "$cmd" in
          battlenet|bnet|battle.net)
            cmd_battlenet "$@"
            ;;
          kill|stop)
            cmd_kill
            ;;
          help|-h|--help)
            usage
            ;;
          *)
            echo "error: unknown command: $cmd" >&2
            usage >&2
            exit 1
            ;;
        esac
      '';
    };
  in {
    options.my.wow-launcher = {
      enable = lib.mkEnableOption "Battle.net umu launcher for an existing Steam Proton prefix";

      compatdataAppId = lib.mkOption {
        type = lib.types.str;
        default = "3077503121";
        description = "Steam compatdata / non-Steam app id that holds the Battle.net + WoW prefix.";
      };

      battleNetExe = lib.mkOption {
        type = lib.types.str;
        default = "Battle.net.exe";
        description = "Battle.net executable name inside Program Files (x86)/Battle.net/.";
      };
    };

    config = lib.mkIf cfg.enable {
      home.packages = [wowLauncher];

      xdg.desktopEntries = {
        battle-net-proton = {
          name = "Battle.net (Proton)";
          comment = "Launch Battle.net via umu/Proton (same Steam prefix)";
          exec = "${lib.getExe wowLauncher} battlenet";
          icon = "applications-games";
          categories = ["Game"];
          terminal = false;
          startupNotify = true;
        };
      };
    };
  };
}
