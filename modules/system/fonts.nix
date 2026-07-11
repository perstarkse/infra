{
  config.flake.nixosModules.fonts = {
    lib,
    pkgs,
    config,
    ...
  }: let
    cfg = config.my.fonts;
  in {
    options.my.fonts.enable = lib.mkEnableOption "system font packages";
    config = lib.mkIf cfg.enable {
      fonts = {
        enableDefaultPackages = true;
        packages = with pkgs; [
          source-code-pro
          font-awesome
          nerd-fonts.fira-code
        ];
      };
    };
  };
}
