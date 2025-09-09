{inputs, ...}: {
  config.flake.nixosModules.home-module = {...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    home-manager = {
      backupFileExtension = "backup";
    };
  };
}
