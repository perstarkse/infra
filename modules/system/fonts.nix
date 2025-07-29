{
  config.flake.nixosModules.fonts = {pkgs, ...}: {
    fonts = {
      enableDefaultPackages = true;
      packages = with pkgs; [
        source-code-pro
        font-awesome
        nerd-fonts.fira-code
      ];
    };
  };
}
