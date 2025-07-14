{
  config.flake.nixosModules.options = {lib, ...}: {
    options.systemSettings.mainUser = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "The username of the primary user for this system.";
      };
      extraSshKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Additional SSH public keys for the main user only, which are added to root's keys.";
      };
    };
  };
}
