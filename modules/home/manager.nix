{inputs, ...}: {
  config.flake.nixosModules.home-module = {pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    home-manager = {
      backupFileExtension = "backup";
    };
  };
}
