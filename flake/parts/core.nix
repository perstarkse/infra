{inputs, ...}: {
  imports = [
    inputs.clan-core.flakeModules.default
    inputs.home-manager.flakeModules.home-manager
    inputs.treefmt-nix.flakeModule
    inputs.nix-topology.flakeModule
    (inputs.import-tree ../../modules)
  ];

  systems = ["x86_64-linux"];
}
