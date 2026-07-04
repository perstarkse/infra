{
  config.flake.nixosModules.ddcutil = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.ddcutil;
  in {
    options.my.ddcutil = {
      enable = lib.mkEnableOption "DDC/CI monitor control via ddcutil";

      ddcui = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Install the ddcui graphical frontend.";
      };
    };

    config = lib.mkIf cfg.enable {
      hardware.i2c.enable = true;

      users.users.${config.my.mainUser.name}.extraGroups = ["i2c"];

      environment.systemPackages =
        [pkgs.ddcutil]
        ++ lib.optional cfg.ddcui pkgs.ddcui;
    };
  };
}
