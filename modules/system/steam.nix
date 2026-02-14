{
  config.flake.nixosModules.steam = {pkgs, ...}: {
    config = {
      programs.steam = {
        enable = true;
        extraCompatPackages = with pkgs; [
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
