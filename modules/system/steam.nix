{
  config.flake.nixosModules.steam = {
    lib,
    pkgs,
    config,
    ...
  }: let
    cfg = config.my.steam;
  in {
    options.my.steam.enable = lib.mkEnableOption "Steam + gamescope";
    config = lib.mkIf cfg.enable {
      programs.steam = {
        enable = true;
        extraCompatPackages = with pkgs.unstable; [
          proton-ge-bin
        ];
        # remotePlay.openFirewall = true;
      };

      programs.gamescope = {
        enable = true;
        capSysNice = true;
      };
    };
  };
}
