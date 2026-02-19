{inputs, ...}: {
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
    ) (lib.filterAttrs (_: cfg: (cfg.pkgs.stdenv.hostPlatform.system or null) == system) nixosConfigs);
    mkCheckBundle = name: checks:
      pkgs.linkFarm name (
        lib.mapAttrsToList (checkName: drv: {
          name = checkName;
          path = drv;
        })
        checks
      );
    routerChecks = import ../../tests/router.nix {
      inherit lib;
      inherit pkgs;
      inherit (inputs.self) nixosModules;
    };
    ioPredeployChecks = import ../../tests/io-predeploy.nix {
      inherit lib;
      inherit pkgs;
      inherit (inputs.self) nixosModules;
    };
    mainTopology = import ../main-topology.nix {
      inherit lib;
      inherit pkgs;
      inherit (inputs.self.topology.${system}.config) nodes;
    };
    networkTopology = import ../network-topology.nix {
      inherit lib;
      inherit pkgs;
      inherit (inputs.self.topology.${system}.config) nodes;
      inherit (inputs.self.topology.${system}.config) networks;
    };
    servicesTopology = import ../services-topology.nix {
      inherit lib;
      inherit pkgs;
      inherit (inputs.self.topology.${system}.config) nodes;
    };
    topologyDiagrams = pkgs.runCommand "topology-diagrams" {} ''
      mkdir -p "$out"
      cp "${mainTopology}/main.svg" "$out/main.svg"
      cp "${networkTopology}/network.svg" "$out/network.svg"
      cp "${servicesTopology}/services.svg" "$out/services.svg"
    '';
    localCheckTargets = {
      router-checks = mkCheckBundle "router-checks" routerChecks;
      predeploy-check = ioPredeployChecks.io-predeploy;
      final-checks = mkCheckBundle "final-checks" (routerChecks // ioPredeployChecks);
    };
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
        inputs.clan-core.packages.${system}.clan-cli
        config.treefmt.build.wrapper
        pkgs.statix
        pkgs.deadnix
      ];
    };

    topology.modules = [
      (import ../topology.nix {
        inherit lib;
      })
    ];

    packages =
      localCheckTargets
      // {
        services-topology = servicesTopology;
        main-topology = mainTopology;
        network-topology = networkTopology;
        topology-diagrams = topologyDiagrams;
      };

    checks = buildChecks // routerChecks // ioPredeployChecks;
  };
}
