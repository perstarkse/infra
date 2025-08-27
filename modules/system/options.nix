{
  config.flake.nixosModules.options = {
    lib,
    config,
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
            type = lib.types.enum ["hyprland" "sway"];
            default = "sway";
            description = "The Wayland session type to use";
          };
        };
      };
    };
  };
}
