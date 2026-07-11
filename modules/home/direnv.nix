{
  config.flake.homeModules.direnv = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.direnv;
  in {
    options.my.direnv.enable = lib.mkEnableOption "direnv + nix-direnv";

    config = lib.mkIf cfg.enable {
      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
      };
    };
  };
}
