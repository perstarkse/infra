{
  config.flake.homeModules.zellij = {
    lib,
    pkgs,
    config,
    ...
  }: let
    cfg = config.my.zellij;

    edgeFlashWasm = pkgs.fetchurl {
      url = "https://github.com/joels-claude-bot/zellij-edge-flash/releases/download/v0.3.0/edge-flash.wasm";
      hash = "sha256-vVuVsNhqQRwLKGrejoBPTB0YI3ksPq8/i8oqeWL1mnI=";
    };
  in {
    options.my.zellij.enable = lib.mkEnableOption "zellij terminal multiplexer with fish integration";

    config = lib.mkIf cfg.enable {
      programs.zellij = {
        enable = true;
        enableFishIntegration = true;
        exitShellOnExit = true;
        attachExistingSession = false;
        settings = {
          show_startup_tips = false;
        };
        # Pin edge-flash.wasm and route Alt+hjkl through the plugin so
        # MoveFocus-at-edge flashes the pane instead of failing silently.
        # See https://github.com/joels-claude-bot/zellij-edge-flash
        extraConfig = ''
          plugins {
              edge-flash location="file:${edgeFlashWasm}"
          }

          load_plugins {
              edge-flash
          }

          keybinds {
              shared_except "locked" {
                  bind "Alt h" "Alt Left"  { MessagePlugin "edge-flash" { payload "left";  launch_new false; }; }
                  bind "Alt l" "Alt Right" { MessagePlugin "edge-flash" { payload "right"; launch_new false; }; }
                  bind "Alt j" "Alt Down"  { MessagePlugin "edge-flash" { payload "down";  launch_new false; }; }
                  bind "Alt k" "Alt Up"    { MessagePlugin "edge-flash" { payload "up";    launch_new false; }; }
              }
          }
        '';
      };
    };
  };
}
