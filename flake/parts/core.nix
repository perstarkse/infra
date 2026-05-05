{inputs, ...}: {
  imports = [
    inputs.clan-core.flakeModules.default
    inputs.home-manager.flakeModules.home-manager
    inputs.treefmt-nix.flakeModule
    (inputs.import-tree ../../modules)
  ];

  systems = ["x86_64-linux"];

  flake.lib.exposure = import ../lib/exposure.nix {inherit (inputs.nixpkgs) lib;};

  # Wrap vpn-confinement to set networking.enableIPv6 before it accesses it
  # (vpn-confinement has a bug: it reads config.networking.enableIPv6 at module load time)
  flake.nixosModules.vpn-confinement = {
    imports = [inputs.vpn-confinement.nixosModules.default];
    networking.enableIPv6 = true;
  };
}
