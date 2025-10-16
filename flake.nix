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

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

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

    minne = {
      url = "github:perstarkse/minne?ref=development";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    NixVirt = {
      url = "https://flakehub.com/f/AshleyYakeley/NixVirt/*.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    vars-helper = {
      url = "github:perstarkse/clan-vars-helper";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };

    sway-focus-flash = {
      url = "github:perstarkse/sway-focus-flash";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-minecraft.url = "github:Infinidoge/nix-minecraft";

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    niri = {
      url = "https://github.com/sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    flake-parts,
    clan-core,
    home-manager,
    private-infra,
    vars-helper,
    ...
  } @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} ({config, ...}: {
      imports = [
        clan-core.flakeModules.default
        home-manager.flakeModules.home-manager
        inputs.treefmt-nix.flakeModule
        (inputs.import-tree ./modules)
      ];

      flake.clan = {
        meta.name = "heliosphere";

        specialArgs = {
          modules = config.flake;
          inherit private-infra;
          inherit vars-helper;
        };

        inventory = {
          machines = {
            oumuamua = {
              deploy.targetHost = "root@192.168.101.48";
              deploy.buildHost = "root@localhost";
              tags = ["server"];
            };
            io = {
              deploy.targetHost = "root@io.lan";
              deploy.buildHost = "root@localhost";
              tags = ["server"];
            };
            makemake = {
              deploy.targetHost = "root@makemake.lan";
              deploy.buildHost = "root@localhost";
              tags = ["server"];
            };
            charon = {
              deploy.targetHost = "root@localhost";
              tags = ["client"];
            };
            ariel = {
              deploy.targetHost = "root@10.0.0.110";
              deploy.buildHost = "root@localhost";
              tags = ["client"];
            };
          };

          instances = {
            clan-cache = {
              module = {
                name = "trusted-nix-caches";
                input = "clan-core";
              };
              roles.default.tags.all = {};
            };
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

      systems = ["x86_64-linux"];

      perSystem = {
        pkgs,
        system,
        config,
        ...
      }: let
        inherit (pkgs) lib;
        nixosConfigs = config.flake.nixosConfigurations or {};
        buildChecks = lib.mapAttrs (
          _: cfg: cfg.config.system.build.toplevel
        ) (lib.filterAttrs (_: cfg: (cfg.pkgs.system or null) == system) nixosConfigs);
      in {
        treefmt = {
          projectRootFile = "flake.nix";
          programs = {
            alejandra.enable = true;
            statix.enable = true;
            deadnix.enable = true;
          };
        };

        formatter = config.treefmt.build.wrapper;

        devShells.default = pkgs.mkShell {
          packages = [
            clan-core.packages.${system}.clan-cli
            config.treefmt.build.wrapper
            pkgs.statix
            pkgs.deadnix
          ];
        };

        # Flake checks: treefmt (module-provided) + per-host builds
        checks = buildChecks;
      };
    });
}
