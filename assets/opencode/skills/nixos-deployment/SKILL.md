---
name: nixos-deployment
description: Deploy NixOS machines in the heliosphere homelab. Use when deploying changes with machine-update, running preflight checks, rendering deployment plans, rolling back failed deploys, or testing deployments in VMs. Covers the full deploy pipeline from nix flake check through post-deploy verification.
---

# NixOS Deployment

Deploy one or more NixOS machines using the opinionated `machine-update` pipeline.

## Quick reference

```bash
nix flake check                        # Validate everything
machine-update-plan <host>             # Preview what will run
machine-update-plan <host> --explain   # Show resolved check plan
machine-update <host>                  # Deploy with preflight checks
machine-update <host> --force          # Skip checks, deploy now
machine-update <host> --checks-only    # Run checks only, skip deploy
```

On the router (`io`), always include `--base-ref` for dynamic detectors:
```bash
machine-update io --base-ref $(git rev-parse main)
```

## Deployment pipeline

### Step 1: Validation
```
nix flake check
```

Catches Nix evaluation errors, type mismatches, module assertion failures (e.g. missing `lanOnly`/`public` on vhosts). Always run this before deploying.

### Step 2: Plan
```
machine-update-plan <host>
```

Resolves the machine's profile tags to a checklist. Each tag maps to one or more checks:
- `check-profile-fast` → fast static checks (flake check)
- `check-profile-garage` → garage cluster health
- `check-profile-politikerstod` → politikerstod distributed tests
- `check-profile-wireguard` → wireguard connectivity tests
- `check-profile-paperless` → paperless integration tests
- `check-profile-backups` → backup integrity checks
- `check-profile-io-final` → mandatory io safety gate (router + io-predeploy)
- `check-profile-io-predeploy` → io predeploy checks (HTTP availability, DNS)

The plan renderer shows `[PASS]`, `[FAIL]`, `[SKIP]`, `[WARN]` per check.

### Step 3: Deploy
```
machine-update <host>
```

Runs the plan's preflight checks, then deploys via `clan machines update <host>`. If any required check fails, deployment is blocked. Use `--force` to skip checks.

**Important**: The `io` machine always requires the `check-profile-io-final` tag — this includes the mandatory router check and io-predeploy gate. Force-blocked for io unless `--force` is used.

### Step 4: Verify
After deploy, verify the service is healthy:
```bash
systemctl status <service> --host root@<host>.lan
curl -sf https://<domain>/health
```

## Rollback

If a deploy breaks something:
```bash
# On the target machine
sudo nixos-rebuild switch --rollback
# Or specify a generation
sudo nixos-rebuild switch --rollback 42
```

## VM testing

Before deploying to physical hardware, test in a VM:
```bash
nixos-rebuild build-vm --flake .#<host>
./result/bin/run-<host>-vm
```

The VM uses the same config as the target, minus hardware-specific settings. Useful for catching service startup issues before they hit production.

## Key constraints

- **io deployments always require final-checks** — the io-predeploy check is mandatory for router safety. It verifies HTTP availability and DNS resolution for exposed services.
- **Force is allowed but logged** — `--force` skips checks but the deployment is still recorded.
- **Never deploy io at the same time as other machines** — io is the router. If it goes down, other machines can't resolve DNS or reach the internet.

## Common pitfalls

- **Forgot `nix flake check` before deploy**: Catches assertion failures (vhost configs, firewall conflicts) that would fail at deploy time anyway.
- **Deployed io without base-ref**: Dynamic detectors compare against main. Without `--base-ref`, changes may not be caught.
- **Didn't stop dependent services**: If updating a database or reverse proxy, stop dependent services first to avoid cascading failures.
