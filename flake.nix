{
  description = "A dendritic clan configuration with flake-parts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
    };

    clan-core = {
      url = "git+https://git.clan.lol/clan/clan-core";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };

    import-tree.url = "github:vic/import-tree";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix = {
      url = "github:danth/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland.url = "github:hyprwm/Hyprland";
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "hyprland";
    };
  };

  outputs = {
    self,
    flake-parts,
    clan-core,
    home-manager,
    ...
  } @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} ({config, ...}: {
      imports = [
        clan-core.flakeModules.default
        home-manager.flakeModules.home-manager
        (inputs.import-tree ./modules)
      ];

      flake.clan = {
        meta.name = "heliosphere";

        specialArgs = {
          modules = config.flake;
        };

        inventory = {
          machines.oumuamua = {
            deploy.targetHost = "root@192.168.122.67";
            tags = ["server"];
          };
        };
      };
      systems = ["x86_64-linux" "aarch64-linux"];

      perSystem = {
        pkgs,
        system,
        ...
      }: {
        devShells.default = pkgs.mkShell {
          packages = [clan-core.packages.${system}.clan-cli];
        };
      };
    });
}
