{inputs, ...}: {
  imports = [
    inputs.clan-core.flakeModules.default
    inputs.home-manager.flakeModules.home-manager
    inputs.treefmt-nix.flakeModule
    (inputs.import-tree ../../modules)
  ];

  systems = ["x86_64-linux"];

  flake.lib.exposure = import ../lib/exposure.nix {inherit (inputs.nixpkgs) lib;};
  flake.lib.versions = import ../lib/versions.nix;
}
