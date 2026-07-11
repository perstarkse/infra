{
  config.flake.homeModules.bitwarden-client = {
    pkgs,
    lib,
    config,
    ...
  }: let
    cfg = config.my.bitwarden-client;
  in {
    options.my.bitwarden-client.enable = lib.mkEnableOption "bitwarden desktop client";

    config = lib.mkIf cfg.enable {
      home.packages = with pkgs; [
        bitwarden-desktop
      ];
    };
  };
}
