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
    garageChecks = import ../../tests/garage.nix {
      inherit lib;
      inherit pkgs;
      inherit (inputs.self) nixosModules;
    };
    politikerstodDistributedChecks = import ../../tests/politikerstod-distributed.nix {
      inherit lib;
      inherit pkgs;
      inherit (inputs.self) nixosModules;
      politikerstodPackage = inputs.politikerstod.packages.${system}.default;
    };
    wireguardSystemChecks = import ../../tests/wireguard-system.nix {
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
      garage-checks = mkCheckBundle "garage-checks" garageChecks;
      politikerstod-checks = mkCheckBundle "politikerstod-checks" politikerstodDistributedChecks;
      wireguard-checks = mkCheckBundle "wireguard-checks" wireguardSystemChecks;
    };

    machineUpdateScript = pkgs.writeShellApplication {
      name = "machine-update";
      runtimeInputs = [
        inputs.clan-core.packages.${system}.clan-cli
        pkgs.python3
      ];
      text = ''
                set -euo pipefail

                PROFILE_TAG_PREFIX="check-profile-"
                DEFAULT_PROFILE_TAG="check-profile-fast"

                show_usage() {
                  local exit_code="''${1:-1}"

                  echo "Usage: machine-update <machine> [options] [-- <extra clan flags>]"
                  echo "       machine-update --clan-help"
                  echo ""
                  echo "Deploy a machine with profile-driven preflight checks."
                  echo ""
                  echo "Options:"
                  echo "  --force       Skip all preflight checks and deploy immediately"
                  echo "  --checks-only Run preflight checks only, skip deploy"
                  echo "  --clan-help   Show help for 'clan machines update'"
                  echo "  -h, --help    Show this help message"
                  echo ""
                  echo "Profile tags are read from clan inventory tags with prefix '$PROFILE_TAG_PREFIX'."
                  echo "Any args after '--' are forwarded to 'clan machines update'."
                  echo ""
                  echo "Examples:"
                  echo "  machine-update io"
                  echo "  machine-update io --checks-only"
                  echo "  machine-update io --force"
                  echo "  machine-update ariel -- --debug"
                  exit "$exit_code"
                }

                FORCE=""
                CHECKS_ONLY=""
                CLAN_HELP=""
                MACHINE=""
                EXTRA_CLAN_ARGS=()

                AVAILABLE_MACHINES=()
                KNOWN_MACHINE_LIST=""
                PROFILE_TAGS=()
                REQUIRED_CHECKS=()

                refresh_machine_lists() {
                  local all_machines_raw=""
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
                      KNOWN_MACHINE_LIST+=", "
                    fi
                    KNOWN_MACHINE_LIST+="$machine"
                  done
                }

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

                add_check_target() {
                  local target="$1"

                  if ! array_contains "$target" "''${REQUIRED_CHECKS[@]}"; then
                    REQUIRED_CHECKS+=("$target")
                  fi
                }

                is_known_machine() {
                  local machine="$1"
                  array_contains "$machine" "''${AVAILABLE_MACHINES[@]}"
                }

                resolve_profile_checks() {
                  local machine="$1"
                  local tags_json=""
                  local profile=""

                  tags_json="$(clan select --flake . "clan.inventory.machines.$machine.tags")"

                  mapfile -t PROFILE_TAGS < <(
                    printf '%s' "$tags_json" \
                      | ${pkgs.python3}/bin/python3 -c 'import json, sys
        data = json.load(sys.stdin)
        for tag in data:
            if isinstance(tag, str) and tag.startswith("check-profile-"):
                print(tag)
        '
                  )

                  if [[ ''${#PROFILE_TAGS[@]} -eq 0 ]]; then
                    PROFILE_TAGS=("$DEFAULT_PROFILE_TAG")
                  fi

                  REQUIRED_CHECKS=()
                  for profile in "''${PROFILE_TAGS[@]}"; do
                    case "$profile" in
                      check-profile-fast)
                        ;;
                      check-profile-router)
                        add_check_target "router-checks"
                        ;;
                      check-profile-io-predeploy)
                        add_check_target "predeploy-check"
                        ;;
              check-profile-io-final)
                add_check_target "final-checks"
                ;;
              check-profile-garage)
                add_check_target "garage-checks"
                ;;
              check-profile-politikerstod)
                add_check_target "politikerstod-checks"
                ;;
              check-profile-wireguard)
                add_check_target "wireguard-checks"
                ;;
              *)
                echo "Error: unknown check profile '$profile' on machine '$machine'"
                echo "Known profiles: check-profile-fast, check-profile-router, check-profile-io-predeploy, check-profile-io-final, check-profile-garage, check-profile-politikerstod, check-profile-wireguard"
                exit 2
                ;;
            esac
                  done
                }

                run_preflight_checks() {
                  local check_target=""

                  echo ""
                  echo "--- Running nix fmt (auto-fix formatting) ---"
                  nix fmt

                  echo ""
                  echo "--- Verifying treefmt check ---"
                  nix build "path:.#checks.${system}.treefmt" --no-link --quiet

                  if [[ ''${#REQUIRED_CHECKS[@]} -eq 0 ]]; then
                    echo ""
                    echo "--- No additional profile checks required ---"
                    return
                  fi

                  echo ""
                  echo "--- Resolved profile checks ---"
                  for check_target in "''${REQUIRED_CHECKS[@]}"; do
                    echo ""
                    echo "--- Running $check_target ---"
                    nix build "path:.#$check_target" --no-link --quiet
                  done
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

                if [[ -z "$MACHINE" ]]; then
                  echo "Error: machine name is required"
                  show_usage 1
                fi

                if [[ -n "$CHECKS_ONLY" && -n "$FORCE" ]]; then
                  echo "Error: --checks-only cannot be combined with --force"
                  exit 2
                fi

                refresh_machine_lists

                if ! is_known_machine "$MACHINE"; then
                  echo "Error: unknown machine '$MACHINE'"
                  echo "Known machines: $KNOWN_MACHINE_LIST"
                  exit 2
                fi

                resolve_profile_checks "$MACHINE"

                echo "=== Machine Update: $MACHINE ==="

                if [[ -z "$FORCE" ]]; then
                  run_preflight_checks
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

    checks =
      buildChecks
      // routerChecks
      // ioPredeployChecks
      // garageChecks
      // politikerstodDistributedChecks
      // wireguardSystemChecks;
  };
}
