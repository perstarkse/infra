{inputs, ...}: {
  perSystem = {
    pkgs,
    system,
    config,
    ...
  }: let
    # MinIO is used as an S3-compatible backend in backup/paperless tests and
    # is marked insecure in nixpkgs 26.05. Permit it on the perSystem pkgs so
    # the test framework can build the package; the real machine configurations
    # don't reference minio, so this doesn't widen the security surface.
    # electron 39.8.10 is EOL in nixpkgs 26.05; bitwarden-desktop pins to it.
    # Allow it here until upstream bumps the electron version.
    pkgs = import inputs.nixpkgs {
      localSystem = {inherit system;};
      config = {
        allowUnfree = true;
        nvidia.acceptLicense = true;
        permittedInsecurePackages = [
          "minio-2025-10-15T17-29-55Z"
          "electron-39.8.10"
        ];
      };
    };

    inherit (pkgs) lib;
    nixosConfigs = inputs.self.nixosConfigurations or {};
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
    routerEndpointsChecks = import ../../tests/router-endpoints.nix {
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
    sednaFailoverChecks = import ../../tests/sedna-failover.nix {
      inherit lib;
      inherit pkgs;
      inherit (inputs.self) nixosModules;
    };
    autoSuspendChecks = import ../../tests/auto-suspend.nix {
      inherit lib;
      inherit pkgs;
      inherit (inputs.self) nixosModules;
    };
    accountedSystemChecks = import ../../tests/accounted-system.nix {
      inherit lib;
      inherit pkgs;
      inherit (inputs.self) nixosModules;
    };
    endpointsManifestData = inputs.self.lib.endpoints.mkEndpointsManifest systemNixosConfigs;

    endpointsManifest = pkgs.writeText "endpoints-manifest.json" (builtins.toJSON endpointsManifestData);

    endpointsManifestValidator = ../../lib/endpoints-manifest-validator.py;

    endpointsManifestCheck =
      pkgs.runCommand "endpoints-manifest-check" {
        nativeBuildInputs = [pkgs.python3];
        manifest = endpointsManifest;
      } ''
        python3 ${endpointsManifestValidator} "$manifest"
        touch $out
      '';

    endpointsListPy = ../../lib/endpoints-list.py;

    endpointsListScript = pkgs.writeShellApplication {
      name = "endpoints-list";
      runtimeInputs = [pkgs.python3];
      text = ''
        set -euo pipefail
        exec python3 ${endpointsListPy} ${endpointsManifest}
      '';
    };

    # Run the sedna Cloudflare-DNS failover drill in a NixOS VM test.
    failoverDrillScript = pkgs.writeShellApplication {
      name = "failover-drill";
      runtimeInputs = [pkgs.nix];
      text = ''
        set -euo pipefail

        if [ ! -f flake.nix ]; then
          echo "ERROR: run failover-drill from the infra repo root" >&2
          exit 1
        fi

        MODE="dry-run"

        show_usage() {
          local exit_code="''${1:-1}"
          echo "Usage: failover-drill [--dry-run|--broken-token]"
          echo ""
          echo "Run the sedna Cloudflare-DNS failover drill in a NixOS VM test."
          echo ""
          echo "Modes:"
          echo "  --dry-run       Simulate heartbeat loss and show the exact Cloudflare"
          echo "                  API sequence with --dry-run; asserts no DNS change and"
          echo "                  no state file mutation"
          echo "  --broken-token  Verify a broken Cloudflare token fails loudly instead of"
          echo "                  silently (missing token file and invalid token)"
          echo ""
          echo "A live mode against a scratch Cloudflare zone is not wired yet: it needs a"
          echo "scratch zone and a token scoped to it (see tests/sedna-failover.nix)."
          exit "$exit_code"
        }

        while [[ $# -gt 0 ]]; do
          case "$1" in
            -h|--help)
              show_usage 0
              ;;
            --dry-run)
              MODE="dry-run"
              shift
              ;;
            --broken-token)
              MODE="broken-token"
              shift
              ;;
            *)
              echo "Unknown option: $1" >&2
              show_usage 2
              ;;
          esac
        done

        case "$MODE" in
          dry-run)
            echo "==> Failover drill: dry-run (heartbeat loss simulation, no state mutation)"
            nix build --no-link -L "path:.#checks.${system}.sedna-failover-drill-dry-run"
            ;;
          broken-token)
            echo "==> Failover drill: broken token (must fail loudly, not silently)"
            nix build --no-link -L "path:.#checks.${system}.sedna-failover-drill-broken-token"
            ;;
        esac

        echo "==> Failover drill passed"
      '';
    };

    localCheckTargets = {
      endpoints-manifest-check = endpointsManifestCheck;
      router-checks = mkCheckBundle "router-checks" routerChecks;
      predeploy-check = mkCheckBundle "predeploy-check" ioPredeployChecks;
      final-checks = mkCheckBundle "final-checks" (routerChecks // ioPredeployChecks);
      garage-checks = mkCheckBundle "garage-checks" garageChecks;
      politikerstod-checks = mkCheckBundle "politikerstod-checks" politikerstodDistributedChecks;
      wireguard-checks = mkCheckBundle "wireguard-checks" wireguardSystemChecks;
      router-endpoints-checks = mkCheckBundle "router-endpoints-checks" routerEndpointsChecks;
      paperless-checks = mkCheckBundle "paperless-checks" paperlessSystemChecks;
      backups-checks = mkCheckBundle "backups-checks" backupsSystemChecks;
      backups-multi-checks = mkCheckBundle "backups-multi-checks" {
        inherit (backupsSystemChecks) backups-multi-backend;
      };
      backups-failure-checks = mkCheckBundle "backups-failure-checks" {
        inherit (backupsSystemChecks) backups-failing-backend;
      };
      mailserver-checks = mkCheckBundle "mailserver-checks" mailserverSystemChecks;
      sedna-failover-checks = mkCheckBundle "sedna-failover-checks" sednaFailoverChecks;
      auto-suspend-checks = mkCheckBundle "auto-suspend-checks" autoSuspendChecks;
      accounted-checks = mkCheckBundle "accounted-checks" accountedSystemChecks;
    };

    machineUpdatePlanResolverPy = pkgs.writeText "machine-update-plan-resolver.py" ''
      import json
      import os
      import pathlib

      profile_to_checks = {
          "check-profile-fast": [],
          "check-profile-router": ["router-checks", "router-endpoints-checks"],
          "check-profile-io-predeploy": ["predeploy-check"],
          "check-profile-io-final": ["final-checks", "router-endpoints-checks", "endpoints-manifest-check"],
          "check-profile-garage": ["garage-checks"],
          "check-profile-politikerstod": ["politikerstod-checks"],
          "check-profile-wireguard": ["wireguard-checks"],
          "check-profile-paperless": ["paperless-checks"],
          "check-profile-backups": ["backups-checks", "backups-multi-checks", "backups-failure-checks"],
          "check-profile-mailserver": ["mailserver-checks"],
          "check-profile-sedna": ["sedna-failover-checks"],
          "check-profile-accounted": ["accounted-checks"],
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
              "Mandatory io safety gate (router + io predeploy tests)"
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
          "forceBlockReason": "io deployments always require final-checks (router + io predeploy tests)" if machine == "io" else None,
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
        DRY_RUN=""
        CLAN_HELP=""
        EXPLAIN=""
        BASE_REF=""
        MACHINES_RAW=()
        MACHINES=()
        PLAN_FILES=()
        REQUIRED_CHECKS=()
        PLAN_WARNINGS=()
        FORCE_BLOCKED_MACHINES=()
        FORCE_BLOCK_REASONS=()
        EXTRA_CLAN_ARGS=()

        show_usage() {
          local exit_code="''${1:-1}"
          echo "Usage: machine-update <machine> [<machine> ...] [options] [-- <extra clan flags>]"
          echo "       machine-update --clan-help"
          echo ""
          echo "Deploy one or more machines with profile-driven preflight checks."
          echo ""
          echo "Options:"
          echo "  --force           Skip all preflight checks and deploy immediately"
          echo "  --checks-only     Run preflight checks only, skip deploy"
          echo "  --dry-run         Resolve check plan without building or deploying"
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
            --dry-run)
              DRY_RUN=1
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
              MACHINES_RAW+=("$1")
              shift
              ;;
          esac
        done

        if [[ -n "$CLAN_HELP" ]]; then
          clan machines update --help
          exit 0
        fi

        if [[ ''${#MACHINES_RAW[@]} -eq 0 ]]; then
          echo "Error: at least one machine name is required"
          show_usage 1
        fi

        if [[ -n "$CHECKS_ONLY" && -n "$FORCE" ]]; then
          echo "Error: --checks-only cannot be combined with --force"
          exit 2
        fi

        if [[ -n "$DRY_RUN" && -n "$FORCE" ]]; then
          echo "Error: --dry-run cannot be combined with --force"
          exit 2
        fi

        if [[ -n "$DRY_RUN" && -n "$CHECKS_ONLY" ]]; then
          echo "Error: --dry-run cannot be combined with --checks-only"
          exit 2
        fi

        declare -A MACHINE_SEEN=()
        for machine in "''${MACHINES_RAW[@]}"; do
          if [[ -z "''${MACHINE_SEEN[$machine]-}" ]]; then
            MACHINE_SEEN[$machine]=1
            MACHINES+=("$machine")
          fi
        done

        declare -A CHECK_SEEN=()
        declare -A WARNING_SEEN=()
        PLAN_DIR="$(mktemp -d)"
        PLAN_INDEX=0

        cleanup() {
          rm -rf "$PLAN_DIR"
        }
        trap cleanup EXIT

        for machine in "''${MACHINES[@]}"; do
          PLAN_ARGS=(--json "$machine")
          if [[ -n "$BASE_REF" ]]; then
            PLAN_ARGS+=(--base-ref "$BASE_REF")
          fi

          PLAN_JSON="$(machine-update-plan "''${PLAN_ARGS[@]}")"
          PLAN_FILE="$PLAN_DIR/plan-$PLAN_INDEX.json"
          PLAN_INDEX=$((PLAN_INDEX + 1))
          printf '%s\n' "$PLAN_JSON" > "$PLAN_FILE"
          PLAN_FILES+=("$PLAN_FILE")

          if [[ -n "$FORCE" ]]; then
            FORCE_ALLOWED="$(printf '%s' "$PLAN_JSON" | ${pkgs.python3}/bin/python3 -c 'import json,sys; data=json.load(sys.stdin); print("true" if data.get("forceAllowed", True) else "false")')"
            if [[ "$FORCE_ALLOWED" != "true" ]]; then
              FORCE_BLOCKED_MACHINES+=("$machine")
              FORCE_BLOCK_REASON="$(printf '%s' "$PLAN_JSON" | ${pkgs.python3}/bin/python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("forceBlockReason") or "")')"
              if [[ -n "$FORCE_BLOCK_REASON" ]]; then
                FORCE_BLOCK_REASONS+=("$machine: $FORCE_BLOCK_REASON")
              fi
            fi
          fi

          mapfile -t MACHINE_WARNINGS < <(printf '%s' "$PLAN_JSON" | ${pkgs.python3}/bin/python3 -c 'import json,sys; data=json.load(sys.stdin); [print(w) for w in data.get("warnings", [])]')
          for warning in "''${MACHINE_WARNINGS[@]}"; do
            if [[ ''${#MACHINES[@]} -gt 1 ]]; then
              warning_entry="[$machine] $warning"
            else
              warning_entry="$warning"
            fi
            if [[ -z "''${WARNING_SEEN[$warning_entry]-}" ]]; then
              WARNING_SEEN[$warning_entry]=1
              PLAN_WARNINGS+=("$warning_entry")
            fi
          done

          mapfile -t MACHINE_CHECKS < <(printf '%s' "$PLAN_JSON" | ${pkgs.python3}/bin/python3 -c 'import json,sys; data=json.load(sys.stdin); [print(c) for c in data.get("checksResolved", [])]')
          for check_target in "''${MACHINE_CHECKS[@]}"; do
            if [[ -z "''${CHECK_SEEN[$check_target]-}" ]]; then
              CHECK_SEEN[$check_target]=1
              REQUIRED_CHECKS+=("$check_target")
            fi
          done
        done

        if [[ -n "$FORCE" && ''${#FORCE_BLOCKED_MACHINES[@]} -gt 0 ]]; then
          if [[ ''${#FORCE_BLOCKED_MACHINES[@]} -eq 1 ]]; then
            machine_name="''${FORCE_BLOCKED_MACHINES[0]}"
            echo "Error: --force is not allowed for machine '$machine_name'"
          else
            printf "Error: --force is not allowed for machines:"
            for machine in "''${FORCE_BLOCKED_MACHINES[@]}"; do
              printf " %s" "$machine"
            done
            printf "\n"
          fi
          for reason in "''${FORCE_BLOCK_REASONS[@]}"; do
            echo "Reason: $reason"
          done
          exit 2
        fi

        if [[ -n "$EXPLAIN" ]]; then
          echo ""
          echo "--- Resolved update plans ---"
          for index in "''${!MACHINES[@]}"; do
            machine="''${MACHINES[$index]}"
            plan_file="''${PLAN_FILES[$index]}"
            echo ""
            echo "[$machine]"
            ${pkgs.python3}/bin/python3 "${machineUpdatePlanRenderPy}" < "$plan_file"
          done

          if [[ ''${#MACHINES[@]} -gt 1 ]]; then
            echo ""
            echo "Combined checks (deduplicated):"
            echo "- treefmt"
            for check_target in "''${REQUIRED_CHECKS[@]}"; do
              echo "- $check_target"
            done
          fi
          exit 0
        fi

        if [[ -n "$DRY_RUN" ]]; then
          echo ""
          echo "--- Dry run: resolved check plan (no builds, no deploy) ---"
          for index in "''${!MACHINES[@]}"; do
            machine="''${MACHINES[$index]}"
            plan_file="''${PLAN_FILES[$index]}"
            echo ""
            echo "[$machine]"
            ${pkgs.python3}/bin/python3 "${machineUpdatePlanRenderPy}" < "$plan_file"
          done

          if [[ ''${#MACHINES[@]} -gt 1 ]]; then
            echo ""
            echo "Combined checks (deduplicated):"
            echo "- treefmt"
            for check_target in "''${REQUIRED_CHECKS[@]}"; do
              echo "- $check_target"
            done
          fi

          echo ""
          echo "(dry run complete -- no actions taken)"
          exit 0
        fi

        if [[ ''${#PLAN_WARNINGS[@]} -gt 0 ]]; then
          echo ""
          echo "--- Plan warnings (non-blocking) ---"
          for warning in "''${PLAN_WARNINGS[@]}"; do
            echo "WARN: $warning"
          done
        fi

        printf '=== Machine Update:'
        for machine in "''${MACHINES[@]}"; do
          printf ' %s' "$machine"
        done
        printf ' ===\n'

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
        for machine in "''${MACHINES[@]}"; do
          echo ""
          echo "--- Deploying $machine ---"
          clan machines update "$machine" "''${EXTRA_CLAN_ARGS[@]}"
        done
      '';
    };
  in {
    clan.pkgs = import inputs.nixpkgs {
      localSystem = {inherit system;};
      config = {
        allowUnfree = true;
        nvidia.acceptLicense = true;
        # electron 39.8.10 is EOL in nixpkgs 26.05; bitwarden-desktop pins to it.
        # Allow it here until upstream bumps the electron version.
        permittedInsecurePackages = [
          "electron-39.8.10"
        ];
      };
    };

    treefmt = {
      projectRootFile = "flake.nix";
      programs = {
        alejandra.enable = true;
        statix.enable = true;
        deadnix.enable = true;
      };
      build.check = self:
        pkgs.runCommandLocal "treefmt-check" {
          buildInputs = [pkgs.git pkgs.git-lfs config.treefmt.build.wrapper];
          meta.description = "Check that the project tree is formatted";
        } ''
          set -e
          PRJ=$TMP/project
          cp -r ${self} $PRJ
          chmod -R a+w $PRJ
          cd $PRJ
          # Remove all embedded .git dirs so a fresh repo can be initialized for diff detection
          find . -name .git -prune -exec rm -rf {} +
          export HOME=$TMPDIR
          git config --global user.name Nix
          git config --global user.email nix@localhost
          git config --global init.defaultBranch main
          git init --quiet
          git add .
          git commit -m init --quiet
          export LANG=C.UTF-8
          export LC_ALL=C.UTF-8
          treefmt --version
          treefmt --no-cache
          git status --short
          git --no-pager diff --exit-code
          touch $out
        '';
    };

    formatter = config.treefmt.build.wrapper;

    devShells.default = pkgs.mkShell {
      packages = [
        inputs.clan-core.packages.${system}.clan-cli
        config.treefmt.build.wrapper
        pkgs.statix
        pkgs.deadnix
        pkgs.gnutar
        pkgs.gzip
        machineUpdatePlanScript
        machineUpdateScript
        endpointsListScript
      ];
    };

    packages =
      localCheckTargets
      // {
        endpoints-manifest = endpointsManifest;
        machine-update-plan = machineUpdatePlanScript;
        machine-update = machineUpdateScript;
        endpoints-list = endpointsListScript;
        failover-drill = failoverDrillScript;
      };

    apps.failover-drill = {
      type = "app";
      program = "${failoverDrillScript}/bin/failover-drill";
      meta.description = "Run the sedna Cloudflare-DNS failover drill (dry-run or broken-token) in a NixOS VM test";
    };

    checks =
      {inherit endpointsManifestCheck;}
      // buildChecks
      // routerChecks
      // ioPredeployChecks
      // garageChecks
      // politikerstodDistributedChecks
      // wireguardSystemChecks
      // routerEndpointsChecks
      // paperlessSystemChecks
      // backupsSystemChecks
      // mailserverSystemChecks
      // sednaFailoverChecks
      // autoSuspendChecks;
  };
}
