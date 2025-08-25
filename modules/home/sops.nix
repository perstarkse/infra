{inputs, ...}: {
  config.flake.homeModules.sops = {...}: {
    imports = [inputs.sops-nix.homeManagerModules.sops];
  };
}
