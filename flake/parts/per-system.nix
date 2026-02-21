{inputs, ...}: {
  perSystem = {
    pkgs,
    system,
    config,
    ...
  }: let
    inherit (pkgs) lib;
    nixosConfigs = config.flake.nixosConfigurations or {};
    systemNixosConfigs =
      lib.filterAttrs (_: cfg: (cfg.pkgs.stdenv.hostPlatform.system or null) == system) nixosConfigs;
    buildChecks = lib.mapAttrs (_: cfg: cfg.config.system.build.toplevel) systemNixosConfigs;
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
                  echo "  --checks-only Run preflight checks only, skip deploy"
                  echo "  --clan-help Show help for 'clan machines update'"
                  echo "  -h, --help Show this help message"
                  echo ""
                  echo "Any args after '--' are forwarded to 'clan machines update'."
                  echo ""
                  echo "Examples:"
                  echo "  machine-update io              # Deploy io with checks"
                  echo "  machine-update io --checks-only  # Run checks without deploy"
                  echo "  machine-update io --force      # Deploy io, skipping checks"
                  echo "  machine-update makemake        # Deploy makemake with fast checks"
                  echo "  machine-update ariel -- --debug  # Forward extra clan args"
                  exit "$exit_code"
                }

                FORCE=""
                CHECKS_ONLY=""
                CLAN_HELP=""
                MACHINE=""
                EXTRA_CLAN_ARGS=()

                refresh_machine_lists() {
                  local all_machines_raw=""
                  local all_machines_json=""
                  local all_machines_csv=""
                  local all_machines_selector=""
                  local machine_router_value=""
                  local machine=""

                  all_machines_raw="$(clan machines list)"
                  if [[ -z "$all_machines_raw" ]]; then
                    echo "Error: unable to determine managed machines from clan inventory"
                    exit 2
                  fi

                  mapfile -t AVAILABLE_MACHINES < <(printf '%s\n' "$all_machines_raw" | sed '/^$/d')
                  if [[ ''${#AVAILABLE_MACHINES[@]} -eq 0 ]]; then
                    echo "Error: no machines found in clan inventory"
                    exit 2
                  fi

                  KNOWN_MACHINE_LIST=""
                  for machine in "''${AVAILABLE_MACHINES[@]}"; do
                    if [[ -n "$KNOWN_MACHINE_LIST" ]]; then
                      KNOWN_MACHINE_LIST+="; "
                    fi
                    KNOWN_MACHINE_LIST+="$machine"
                  done

                  all_machines_csv="$(printf '%s\n' "''${AVAILABLE_MACHINES[@]}" | paste -sd ',' -)"
                  all_machines_selector="{$(printf '%s' "$all_machines_csv")}"
                  all_machines_json="$(clan select --flake . "nixosConfigurations.$all_machines_selector.config.my.router.enable" 2>/dev/null || true)"

                  ROUTER_ENABLED_MACHINES=()
                  for machine in "''${AVAILABLE_MACHINES[@]}"; do
                    machine_router_value="$(
                      printf '%s' "$all_machines_json" \
                        | ${pkgs.python3}/bin/python3 -c 'import json, sys
        try:
            data = json.load(sys.stdin)
        except Exception:
            print("missing")
            raise SystemExit(0)
        machine = sys.argv[1]
        value = data.get(machine, "missing") if isinstance(data, dict) else "missing"
        if value is True:
            print("true")
        elif value is False:
            print("false")
        else:
            print("missing")' "$machine"
                    )"

                    if [[ "$machine_router_value" == "missing" ]]; then
                      machine_router_value="$(clan select --flake . "nixosConfigurations.$machine.config.my.router.enable" 2>/dev/null || true)"
                    fi

                    if [[ "$machine_router_value" == "true" ]]; then
                      ROUTER_ENABLED_MACHINES+=("$machine")
                    fi
                  done
                }

                AVAILABLE_MACHINES=()
                ROUTER_ENABLED_MACHINES=()
                KNOWN_MACHINE_LIST=""

                array_contains() {
                  local needle="$1"
                  shift
                  local value=""

                  for value in "$@"; do
                    if [[ "$value" == "$needle" ]]; then
                      return 0
                    fi
                  done

                  return 1
                }

                is_known_machine() {
                  local machine="$1"
                  array_contains "$machine" "''${AVAILABLE_MACHINES[@]}"
                }

                is_router_machine() {
                  local machine="$1"
                  array_contains "$machine" "''${ROUTER_ENABLED_MACHINES[@]}"
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
                    --checks-only)
                      CHECKS_ONLY=1
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

                refresh_machine_lists

                if [[ -n "$CHECKS_ONLY" && -n "$FORCE" ]]; then
                  echo "Error: --checks-only cannot be combined with --force"
                  exit 2
                fi

                if [[ -z "$MACHINE" ]]; then
                  echo "Error: machine name is required"
                  show_usage 1
                fi

                if ! is_known_machine "$MACHINE"; then
                  echo "Error: unknown machine '$MACHINE'"
                  echo "Known machines: $KNOWN_MACHINE_LIST"
                  exit 2
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

                if [[ -n "$CHECKS_ONLY" ]]; then
                  echo ""
                  echo "--- Checks completed; skipping deploy (--checks-only) ---"
                  exit 0
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
