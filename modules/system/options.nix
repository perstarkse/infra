{
  config.flake.nixosModules.options = {
    lib,
    config,
    pkgs,
    ...
  }: {
    options = {
      my = {
        mainUser = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "The username of the primary user for this system.";
          };
          extraSshKeys = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Additional SSH public keys for the main user.";
          };
        };
        listenNetworkAddress = lib.mkOption {
          type = lib.types.str;
          default = "0.0.0.0";
          description = "The network address to listen on.";
        };
        gui = {
          enable = lib.mkEnableOption "Enable GUI session management";
          session = lib.mkOption {
            type = lib.types.enum ["hyprland" "sway" "niri"];
            default = "sway";
            description = "The Wayland session type to use";
          };
          terminal = lib.mkOption {
            type = lib.types.enum ["kitty"];
            default = "kitty";
            description = "The terminal emulator to use in GUI sessions";
          };
          _terminalCommand = lib.mkOption {
            type = lib.types.str;
            default = "kitty";
            description = "The terminal emulator command";
          };
        };
      };
    };

    config = {
      my.gui._terminalCommand =
        if config.my.gui.terminal == "kitty"
        then "${pkgs.kitty}/bin/kitty"
        else "${pkgs.kitty}/bin/kitty";
    };
  };
}
