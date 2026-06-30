{inputs, ...}: {
  config.flake.nixosModules.home-module = {...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    home-manager = {
      useGlobalPkgs = true;
      backupFileExtension = "backup";
      sharedModules = [
        ({osConfig, ...}: {
          home.stateVersion = osConfig.my.stateVersion;
        })
      ];
    };
  };
}
