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

    hyprland.url = "github:hyprwm/Hyprland/v0.50.0?submodules=1";
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "hyprland";
    };

    hyprnstack = {
      url = "github:perstarkse/hyprNStack";
      inputs.hyprland.follows = "hyprland";
    };

    hy3 = {
      url = "github:outfoxxed/hy3?ref=hl0.50.0";
      inputs.hyprland.follows = "hyprland";
    };

    private-infra = {
      url = "git+ssh://git@github.com/perstarkse/private-infra.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    flake-parts,
    clan-core,
    home-manager,
    private-infra,
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
          inherit private-infra;
        };

        inventory = {
          machines.oumuamua = {
            deploy.targetHost = "root@192.168.122.67";
            deploy.buildHost = "root@10.0.0.15";
            tags = ["server"];
          };
          machines.io = {
            deploy.targetHost = "root@10.0.0.1";
            tags = ["server"];
          };
          machines.charon = {
            deploy.targetHost = "root@10.0.0.15";
            tags = ["client"];
          };

          instances = {
            sshd-basic = {
              module = {
                name = "sshd";
                input = "clan-core";
              };
              roles.server.tags.all = {};
              roles.client.tags.all = {};
            };
            user-p = {
              module = {
                name = "users";
                input = "clan-core";
              };
              roles.default.tags.all = {};
              roles.default.settings = {
                user = "p";
                prompt = true;
              };
            };
            admin = {
              roles.default.tags.all = {};
              roles.default.settings = {
                allowedKeys = {
                  "p" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII6uq8nXD+QBMhXqRNywwCa/dl2VVvG/2nvkw9HEPFzn";
                };
              };
            };
            emergency-access = {
              module = {
                name = "emergency-access";
                input = "clan-core";
              };

              roles.default.tags.nixos = {};
            };
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
