{
  config.flake.homeModules.bitwarden-client = {pkgs, ...}: {
    home.packages = with pkgs; [
      bitwarden-desktop
    ];
  };
}
