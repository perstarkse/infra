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
    paperlessSystemChecks = import ../../tests/paperless-system.nix {
      inherit lib;
      inherit pkgs;
      inherit (inputs.self) nixosModules;
    };
    backupsSystemChecks = import ../../tests/backups.nix {
      inherit lib;
      inherit pkgs;
      inherit (inputs.self) nixosModules;
    };
    mailserverSystemChecks = import ../../tests/mailserver-system.nix {
      inherit lib;
      inherit pkgs;
      privateMailserverModule = inputs.private-infra.nixosModules.mailserver;
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
      paperless-checks = mkCheckBundle "paperless-checks" paperlessSystemChecks;
      backups-checks = mkCheckBundle "backups-checks" backupsSystemChecks;
      backups-multi-checks = mkCheckBundle "backups-multi-checks" {
        inherit (backupsSystemChecks) backups-multi-backend;
      };
      backups-failure-checks = mkCheckBundle "backups-failure-checks" {
        inherit (backupsSystemChecks) backups-failing-backend;
      };
      mailserver-checks = mkCheckBundle "mailserver-checks" mailserverSystemChecks;
    };

    machineUpdatePlanResolverPy = pkgs.writeText "machine-update-plan-resolver.py" ''
      import json
      import os
      import pathlib

      profile_to_checks = {
          "check-profile-fast": [],
          "check-profile-router": ["router-checks"],
          "check-profile-io-predeploy": ["predeploy-check"],
          "check-profile-io-final": ["final-checks"],
          "check-profile-garage": ["garage-checks"],
          "check-profile-politikerstod": ["politikerstod-checks"],
          "check-profile-wireguard": ["wireguard-checks"],
          "check-profile-paperless": ["paperless-checks"],
          "check-profile-backups": ["backups-checks", "backups-multi-checks", "backups-failure-checks"],
          "check-profile-mailserver": ["mailserver-checks"],
      }

      machine = os.environ["MU_PLAN_MACHINE"]
      default_profile = os.environ["MU_PLAN_DEFAULT_PROFILE"]
      known_machines = json.loads(os.environ["MU_PLAN_KNOWN_MACHINES_JSON"])
      tags = json.loads(os.environ["MU_PLAN_TAGS_JSON"])
      warnings = list(json.loads(os.environ["MU_PLAN_WARNINGS_JSON"]))
      base_ref_used = os.environ.get("MU_PLAN_BASE_REF_USED", "")
      old_lock_path = os.environ.get("MU_PLAN_OLD_LOCK_PATH", "")
      new_lock_path = os.environ.get("MU_PLAN_NEW_LOCK_PATH", "flake.lock")

      profiles_static = [
          tag for tag in tags if isinstance(tag, str) and tag.startswith("check-profile-")
      ]
      if not profiles_static:
          profiles_static = [default_profile]

      profiles_dynamic = []
      profiles_mandatory = []
      profile_reasons = {}

      for profile in profiles_static:
          profile_reasons.setdefault(profile, []).append(f"Inventory tag '{profile}'")

      if machine == "io":
          profile = "check-profile-io-final"
          profiles_mandatory.append(profile)
          profile_reasons.setdefault(profile, []).append(
              "Mandatory io safety gate (router + io-predeploy)"
          )

      if old_lock_path:
          try:
              old_lock = json.loads(pathlib.Path(old_lock_path).read_text())
              new_lock = json.loads(pathlib.Path(new_lock_path).read_text())

              old_node = old_lock.get("nodes", {}).get("politikerstod", {})
              new_node = new_lock.get("nodes", {}).get("politikerstod", {})

              old_rev = old_node.get("locked", {}).get("rev")
              new_rev = new_node.get("locked", {}).get("rev")
              old_nar = old_node.get("locked", {}).get("narHash")
              new_nar = new_node.get("locked", {}).get("narHash")

              if old_rev != new_rev or old_nar != new_nar:
                  profile = "check-profile-politikerstod"
                  profiles_dynamic.append(profile)
                  detail = f"flake.lock politikerstod changed (rev {old_rev or 'n/a'} -> {new_rev or 'n/a'})"
                  if old_nar != new_nar:
                      detail += "; narHash changed"
                  profile_reasons.setdefault(profile, []).append(detail)
          except Exception as exc:
              warnings.append(f"Lockfile detector failed: {exc}")

      profiles_all = []
      for profile in profiles_static + profiles_dynamic + profiles_mandatory:
          if profile not in profiles_all:
              profiles_all.append(profile)

      unknown_profiles = [profile for profile in profiles_all if profile not in profile_to_checks]
      if unknown_profiles:
          raise SystemExit(
              "Unknown check profile(s): "
              + ", ".join(unknown_profiles)
              + ". Known profiles: "
              + ", ".join(sorted(profile_to_checks))
          )

      checks_resolved = []
      reasons = {}
      mandatory_checks = []

      for profile in profiles_mandatory:
          for check in profile_to_checks[profile]:
              if check not in mandatory_checks:
                  mandatory_checks.append(check)

      for profile in profiles_all:
          for check in profile_to_checks[profile]:
              if check not in checks_resolved:
                  checks_resolved.append(check)
              reasons.setdefault(check, [])
              for reason in profile_reasons.get(profile, []):
                  if reason not in reasons[check]:
                      reasons[check].append(reason)

      plan = {
          "machine": machine,
          "knownMachines": known_machines,
          "baseRefUsed": base_ref_used or None,
          "profilesStatic": profiles_static,
          "profilesDynamic": profiles_dynamic,
          "profilesMandatory": profiles_mandatory,
          "profilesAll": profiles_all,
          "checksBaseline": ["treefmt"],
          "mandatoryChecks": mandatory_checks,
          "checksResolved": checks_resolved,
          "reasons": reasons,
          "forceAllowed": machine != "io",
          "forceBlockReason": "io deployments always require final-checks (router + io-predeploy)" if machine == "io" else None,
          "warnings": warnings,
      }

      print(json.dumps(plan, sort_keys=True))
    '';

    machineUpdatePlanRenderPy = pkgs.writeText "machine-update-plan-render.py" ''
      import json
      import sys

      plan = json.load(sys.stdin)

      print(f"Machine: {plan['machine']}")
      if plan.get("baseRefUsed"):
          print(f"Base ref: {plan['baseRefUsed']}")
      print("Static profiles: " + (", ".join(plan.get("profilesStatic", [])) or "none"))
      print("Dynamic profiles: " + (", ".join(plan.get("profilesDynamic", [])) or "none"))
      print("Mandatory profiles: " + (", ".join(plan.get("profilesMandatory", [])) or "none"))
      print("Checks:")
      print("- treefmt")
      for check in plan.get("checksResolved", []):
          reasons = "; ".join(plan.get("reasons", {}).get(check, [])) or "no reason"
          print(f"- {check} ({reasons})")
      if not plan.get("forceAllowed", True):
          print(f"Force policy: blocked ({plan.get('forceBlockReason', 'policy')})")
      if plan.get("warnings"):
          print("Warnings:")
          for warning in plan["warnings"]:
              print(f"- {warning}")
    '';

    machineUpdatePlanScript = pkgs.writeShellApplication {
      name = "machine-update-plan";
      runtimeInputs = [
        inputs.clan-core.packages.${system}.clan-cli
        pkgs.git
        pkgs.python3
      ];
      text = ''
        set -euo pipefail

        DEFAULT_PROFILE_TAG="check-profile-fast"
        JSON_OUTPUT=""
        MACHINE=""
        BASE_REF_ARG=""
        WARNINGS=()

        show_usage() {
          local exit_code="''${1:-1}"
          echo "Usage: machine-update-plan <machine> [--json] [--base-ref <ref>]"
          echo ""
          echo "Resolve profile tags, dynamic detectors, and checks for a machine update."
          echo ""
          echo "Options:"
          echo "  --json            Output plan as JSON"
          echo "  --base-ref <ref>  Git ref used by lockfile change detectors"
          echo "  -h, --help        Show this help"
          exit "$exit_code"
        }

        while [[ $# -gt 0 ]]; do
          case "$1" in
            -h|--help)
              show_usage 0
              ;;
            --json)
              JSON_OUTPUT=1
              shift
              ;;
            --base-ref)
              if [[ $# -lt 2 ]]; then
                echo "Error: --base-ref requires a value"
                exit 2
              fi
              BASE_REF_ARG="$2"
              shift 2
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

        if [[ -z "$MACHINE" ]]; then
          echo "Error: machine name is required"
          show_usage 1
        fi

        mapfile -t AVAILABLE_MACHINES < <(clan machines list | sed '/^$/d')
        if [[ ''${#AVAILABLE_MACHINES[@]} -eq 0 ]]; then
          echo "Error: unable to determine managed machines from clan inventory"
          exit 2
        fi

        KNOWN_MACHINE_LIST=""
        MACHINE_FOUND=""
        for known_machine in "''${AVAILABLE_MACHINES[@]}"; do
          if [[ -n "$KNOWN_MACHINE_LIST" ]]; then
            KNOWN_MACHINE_LIST+=", "
          fi
          KNOWN_MACHINE_LIST+="$known_machine"
          if [[ "$known_machine" == "$MACHINE" ]]; then
            MACHINE_FOUND=1
          fi
        done

        if [[ -z "$MACHINE_FOUND" ]]; then
          echo "Error: unknown machine '$MACHINE'"
          echo "Known machines: $KNOWN_MACHINE_LIST"
          exit 2
        fi

        TAGS_JSON="$(clan select --flake . "clan.inventory.machines.$MACHINE.tags")"

        BASE_REF_USED=""
        BASE_REF_REQUESTED="''${MACHINE_UPDATE_BASE_REF:-}"
        if [[ -n "$BASE_REF_ARG" ]]; then
          BASE_REF_REQUESTED="$BASE_REF_ARG"
        fi

        if [[ -n "$BASE_REF_REQUESTED" ]]; then
          if git rev-parse --verify --quiet "$BASE_REF_REQUESTED^{commit}" >/dev/null; then
            BASE_REF_USED="$BASE_REF_REQUESTED"
          else
            WARNINGS+=("Unable to resolve requested base ref '$BASE_REF_REQUESTED'; dynamic lockfile detectors disabled.")
          fi
        else
          if BASE_REF_AUTO="$(git merge-base HEAD main 2>/dev/null || true)" && [[ -n "$BASE_REF_AUTO" ]]; then
            BASE_REF_USED="$BASE_REF_AUTO"
          elif BASE_REF_AUTO="$(git rev-parse --verify --quiet HEAD~1 2>/dev/null || true)" && [[ -n "$BASE_REF_AUTO" ]]; then
            BASE_REF_USED="$BASE_REF_AUTO"
          else
            WARNINGS+=("No git baseline found (merge-base/HEAD~1); dynamic lockfile detectors disabled.")
          fi
        fi

        OLD_LOCK_PATH=""
        if [[ -n "$BASE_REF_USED" ]]; then
          OLD_LOCK_PATH="$(mktemp)"
          if ! git show "$BASE_REF_USED:flake.lock" > "$OLD_LOCK_PATH" 2>/dev/null; then
            WARNINGS+=("Unable to read flake.lock at '$BASE_REF_USED'; dynamic lockfile detectors disabled.")
            rm -f "$OLD_LOCK_PATH"
            OLD_LOCK_PATH=""
            BASE_REF_USED=""
          fi
        fi

        cleanup() {
          if [[ -n "$OLD_LOCK_PATH" && -f "$OLD_LOCK_PATH" ]]; then
            rm -f "$OLD_LOCK_PATH"
          fi
        }
        trap cleanup EXIT

        KNOWN_MACHINES_JSON="$(printf '%s\n' "''${AVAILABLE_MACHINES[@]}" | ${pkgs.python3}/bin/python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))')"
        WARNINGS_JSON="$(printf '%s\n' "''${WARNINGS[@]}" | ${pkgs.python3}/bin/python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))')"

        export MU_PLAN_MACHINE="$MACHINE"
        export MU_PLAN_TAGS_JSON="$TAGS_JSON"
        export MU_PLAN_KNOWN_MACHINES_JSON="$KNOWN_MACHINES_JSON"
        export MU_PLAN_DEFAULT_PROFILE="$DEFAULT_PROFILE_TAG"
        export MU_PLAN_WARNINGS_JSON="$WARNINGS_JSON"
        export MU_PLAN_BASE_REF_USED="$BASE_REF_USED"
        export MU_PLAN_OLD_LOCK_PATH="$OLD_LOCK_PATH"
        export MU_PLAN_NEW_LOCK_PATH="flake.lock"

        PLAN_JSON="$(${pkgs.python3}/bin/python3 "${machineUpdatePlanResolverPy}")"

        if [[ -n "$JSON_OUTPUT" ]]; then
          printf '%s\n' "$PLAN_JSON"
          exit 0
        fi

        printf '%s' "$PLAN_JSON" | ${pkgs.python3}/bin/python3 "${machineUpdatePlanRenderPy}"
      '';
    };

    machineUpdateScript = pkgs.writeShellApplication {
      name = "machine-update";
      runtimeInputs = [
        machineUpdatePlanScript
        inputs.clan-core.packages.${system}.clan-cli
        pkgs.python3
      ];
      text = ''
        set -euo pipefail

        FORCE=""
        CHECKS_ONLY=""
        CLAN_HELP=""
        EXPLAIN=""
        BASE_REF=""
        MACHINE=""
        EXTRA_CLAN_ARGS=()

        show_usage() {
          local exit_code="''${1:-1}"
          echo "Usage: machine-update <machine> [options] [-- <extra clan flags>]"
          echo "       machine-update --clan-help"
          echo ""
          echo "Deploy a machine with profile-driven preflight checks."
          echo ""
          echo "Options:"
          echo "  --force           Skip all preflight checks and deploy immediately"
          echo "  --checks-only     Run preflight checks only, skip deploy"
          echo "  --explain         Print resolved check plan and exit"
          echo "  --base-ref <ref>  Baseline for dynamic detectors"
          echo "  --clan-help       Show help for 'clan machines update'"
          echo "  -h, --help        Show this help"
          exit "$exit_code"
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
            --explain)
              EXPLAIN=1
              shift
              ;;
            --base-ref)
              if [[ $# -lt 2 ]]; then
                echo "Error: --base-ref requires a value"
                exit 2
              fi
              BASE_REF="$2"
              shift 2
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

        PLAN_ARGS=(--json "$MACHINE")
        if [[ -n "$BASE_REF" ]]; then
          PLAN_ARGS+=(--base-ref "$BASE_REF")
        fi
        PLAN_JSON="$(machine-update-plan "''${PLAN_ARGS[@]}")"

        FORCE_ALLOWED="$(printf '%s' "$PLAN_JSON" | ${pkgs.python3}/bin/python3 -c 'import json,sys; data=json.load(sys.stdin); print("true" if data.get("forceAllowed", True) else "false")')"
        FORCE_BLOCK_REASON="$(printf '%s' "$PLAN_JSON" | ${pkgs.python3}/bin/python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("forceBlockReason") or "")')"
        if [[ -n "$FORCE" && "$FORCE_ALLOWED" != "true" ]]; then
          echo "Error: --force is not allowed for machine '$MACHINE'"
          if [[ -n "$FORCE_BLOCK_REASON" ]]; then
            echo "Reason: $FORCE_BLOCK_REASON"
          fi
          exit 2
        fi

        if [[ -n "$EXPLAIN" ]]; then
          echo ""
          echo "--- Resolved update plan ---"
          EXPLAIN_PLAN_ARGS=("$MACHINE")
          if [[ -n "$BASE_REF" ]]; then
            EXPLAIN_PLAN_ARGS+=(--base-ref "$BASE_REF")
          fi
          machine-update-plan "''${EXPLAIN_PLAN_ARGS[@]}"
          exit 0
        fi

        mapfile -t PLAN_WARNINGS < <(printf '%s' "$PLAN_JSON" | ${pkgs.python3}/bin/python3 -c 'import json,sys; data=json.load(sys.stdin); [print(w) for w in data.get("warnings", [])]')
        mapfile -t REQUIRED_CHECKS < <(printf '%s' "$PLAN_JSON" | ${pkgs.python3}/bin/python3 -c 'import json,sys; data=json.load(sys.stdin); [print(c) for c in data.get("checksResolved", [])]')

        if [[ ''${#PLAN_WARNINGS[@]} -gt 0 ]]; then
          echo ""
          echo "--- Plan warnings (non-blocking) ---"
          for warning in "''${PLAN_WARNINGS[@]}"; do
            echo "WARN: $warning"
          done
        fi

        echo "=== Machine Update: $MACHINE ==="

        if [[ -z "$FORCE" ]]; then
          echo ""
          echo "--- Running nix fmt (auto-fix formatting) ---"
          nix fmt

          echo ""
          echo "--- Verifying treefmt check ---"
          nix build "path:.#checks.${system}.treefmt" --no-link --quiet

          if [[ ''${#REQUIRED_CHECKS[@]} -eq 0 ]]; then
            echo ""
            echo "--- No additional profile checks required ---"
          else
            echo ""
            echo "--- Running additional profile checks ---"
            for check_target in "''${REQUIRED_CHECKS[@]}"; do
              echo ""
              echo "--- Running $check_target ---"
              nix build "path:.#$check_target" --no-link --quiet
            done
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
        machineUpdatePlanScript
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
        machine-update-plan = machineUpdatePlanScript;
        machine-update = machineUpdateScript;
      };

    checks =
      buildChecks
      // routerChecks
      // ioPredeployChecks
      // garageChecks
      // politikerstodDistributedChecks
      // wireguardSystemChecks
      // paperlessSystemChecks
      // backupsSystemChecks
      // mailserverSystemChecks;
  };
}
