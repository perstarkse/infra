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
    routerEnabledMachines =
      lib.attrNames
      (lib.filterAttrs (_: cfg:
        ((cfg.pkgs.stdenv.hostPlatform.system or null) == system)
        && (lib.attrByPath ["config" "my" "router" "enable"] false cfg))
      nixosConfigs);

    machineUpdateScript = pkgs.writeShellApplication {
      name = "machine-update";
      runtimeInputs = [inputs.clan-core.packages.${system}.clan-cli];
      text = ''
        set -euo pipefail

        show_usage() {
          local exit_code="''${1:-1}"
          echo "Usage: machine-update <machine> [options] [-- <extra clan flags>]"
          echo "       machine-update --clan-help"
          echo ""
          echo "Deploy a machine with preflight checks."
          echo ""
          echo "Options:"
          echo "  --force    Skip all preflight checks and deploy immediately"
          echo "  --clan-help Show help for 'clan machines update'"
          echo "  -h, --help Show this help message"
          echo ""
          echo "Any args after '--' are forwarded to 'clan machines update'."
          echo ""
          echo "Examples:"
          echo "  machine-update io              # Deploy io with checks"
          echo "  machine-update io --force      # Deploy io, skipping checks"
          echo "  machine-update makemake        # Deploy makemake with fast checks"
          echo "  machine-update ariel -- --debug  # Forward extra clan args"
          exit "$exit_code"
        }

        FORCE=""
        CLAN_HELP=""
        MACHINE=""
        EXTRA_CLAN_ARGS=()
        ROUTER_ENABLED_MACHINES=(${lib.concatStringsSep " " routerEnabledMachines})

        is_router_machine() {
          local machine="$1"
          local candidate=""

          for candidate in "''${ROUTER_ENABLED_MACHINES[@]}"; do
            if [[ "$candidate" == "$machine" ]]; then
              return 0
            fi
          done

          return 1
        }

        while [[ $# -gt 0 ]]; do
          case "$1" in
            -h|--help)
              show_usage 0
              ;;
            --force)
              FORCE=1
              shift
              ;;
            --clan-help)
              CLAN_HELP=1
              shift
              ;;
            --)
              shift
              EXTRA_CLAN_ARGS=("$@")
              break
              ;;
            -*)
              echo "Unknown option: $1"
              show_usage 1
              ;;
            *)
              if [[ -z "$MACHINE" ]]; then
                MACHINE="$1"
              else
                echo "Unexpected argument: $1"
                show_usage 1
              fi
              shift
              ;;
          esac
        done

        if [[ -n "$CLAN_HELP" ]]; then
          clan machines update --help
          exit 0
        fi

        if [[ -z "$MACHINE" ]]; then
          echo "Error: machine name is required"
          show_usage 1
        fi

        echo "=== Machine Update: $MACHINE ==="

        if [[ -z "$FORCE" ]]; then
          echo ""
          echo "--- Running nix fmt (auto-fix formatting) ---"
          nix fmt

          echo ""
          echo "--- Verifying treefmt check ---"
          nix build "path:.#checks.${system}.treefmt" --no-link --quiet

          if [[ "$MACHINE" == "io" ]]; then
            echo ""
            echo "--- Running final-checks (router + io-predeploy) ---"
            nix build "path:.#final-checks" --no-link --quiet
          elif is_router_machine "$MACHINE"; then
            echo ""
            echo "--- Running router-checks ---"
            nix build "path:.#router-checks" --no-link --quiet
          else
            echo ""
            echo "--- No additional checks required for '$MACHINE' ---"
          fi
        else
          echo ""
          echo "--- FORCE mode: skipping all checks ---"
        fi

        echo ""
        echo "--- Deploying via clan machines update ---"
        clan machines update "$MACHINE" "''${EXTRA_CLAN_ARGS[@]}"
      '';
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
        machineUpdateScript
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
        machine-update = machineUpdateScript;
      };

    checks = buildChecks // routerChecks // ioPredeployChecks;
  };
}
