{
  description = "Oumu AI Assistant - Self-managing NixOS VM with Openclaw";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-openclaw = {
      url = "github:openclaw/nix-openclaw";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    sops-nix,
    nixos-generators,
    home-manager,
    nix-openclaw,
    ...
  } @ inputs: {
    nixosConfigurations.oumu = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {inherit inputs;};
      modules = [
        (_: {
          nixpkgs.overlays = [nix-openclaw.overlays.default];
        })
        sops-nix.nixosModules.sops
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
        }
        home-manager.nixosModules.home-manager
        ./hardware-configuration.nix
        ./configuration.nix
      ];
    };

    packages.x86_64-linux.qcow2 = nixos-generators.nixosGenerate {
      system = "x86_64-linux";
      format = "qcow";
      modules = [
        sops-nix.nixosModules.sops
        ./configuration.nix
      ];
    };
  };
}
