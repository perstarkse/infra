---
name: running-local-checks
description: Runs local infra validation checks (router and io predeploy) through flake-native shortcut targets.
---

# Running Local Checks

Use these flake-native commands from repo root:

- `nix build path:.#router-checks`
- `nix build path:.#router-endpoints-checks`
- `nix build path:.#predeploy-check`
- `nix build path:.#final-checks`
- `nix build path:.#garage-checks`
- `nix build path:.#politikerstod-checks`
- `nix build path:.#wireguard-checks`
- `nix build path:.#paperless-checks`
- `nix build path:.#backups-checks`
- `nix build path:.#mailserver-checks`
- `nix build path:.#sedna-failover-checks`
- `nix build path:.#auto-suspend-checks`
- `nix build path:.#monitor-resume-checks`
- `nix build path:.#accounted-checks`
- `nix build path:.#endpoints-manifest-check`
- `nix flake check path:.`

## What They Do

- `router-checks`: router integration suite (`router-smoke`, `router-segment-isolation`, `router-segment-policy`, `router-access-port`, `router-nginx-machine-targets`, `router-dns-profiles`, `router-dns-enforcement`, `router-services`, `router-port-forward`, `openchamber-firewall-sources`, `router-wireguard-admin`, `router-wireguard`)
- `router-endpoints-checks`: endpoints system tests (`router-endpoints-smoke`, `router-endpoints-dns-and-vhost`, `router-endpoints-lan-only-enforcement`, `router-endpoints-dns-auto`, `router-endpoints-extra-config`)
- `predeploy-check`: `io-predeploy` test (actual `machines/io/configuration.nix` with test overrides/stubs)
- `final-checks`: router suite + predeploy (safety gate for io)
- `garage-checks`: distributed storage cluster tests
- `politikerstod-checks`: distributed task processor tests
- `wireguard-checks`: wireguard tunnel system tests
- `paperless-checks`: paperless S3 consumption tests
- `backups-checks`: restic backup create/restore, multi-backend, and failure tests
- `mailserver-checks`: private-infra mailserver tests
- `sedna-failover-checks`: sedna maintenance page and DNS failover tests
- `auto-suspend-checks`: auto-suspend idle/load/inhibitor decision tests (short, headless)
- `monitor-resume-checks`: ddcutil resume/keep-awake force-off unless physical-input policy is on; HID vs uinput classification
- `accounted-checks`: Supabase+Accounted compose materialization, env render, Garage provision, migration unit ordering
- `endpoints-manifest-check`: validates endpoints manifest structure and consistency
- `nix flake check path:.`: all checks in flake (includes host builds)

## Change-Based Selection

- Router module changes (`modules/system/router/**`): run `path:.#router-checks`
- Endpoints layer changes (`flake/lib/endpoints*.nix`, `modules/system/options.nix` endpoints options, a service's `my.<svc>.endpoints`): run `path:.#router-endpoints-checks` and `path:.#endpoints-manifest-check`
- `machines/io/configuration.nix` changes: run `path:.#predeploy-check`
- Auto-suspend module changes (`modules/system/auto-suspend.nix`): run `path:.#auto-suspend-checks`
- ddcutil resume/monitor-power/input (`modules/system/ddcutil/**`): run `path:.#monitor-resume-checks`
- Before merge/deploy: run `path:.#final-checks`

## Troubleshooting

- Add `--show-trace` for full evaluation traces.
- Use `path:.#...` (not `.#...`) during local edits to include uncommitted files.

# Deploy Gate Behavior

When deploying machines, always prefer `machine-update` over direct `clan machines update`:

```bash
machine-update <machine>        # With preflight checks
machine-update <machine> --checks-only  # Checks only, no deploy
machine-update <machine> --dry-run  # Show resolved check plan without building
machine-update <machine> --force  # Skip checks
machine-update --clan-help       # Show underlying clan update help
```

## Preflight checks by machine

Checks are resolved from Clan inventory profile tags (`check-profile-*`) and run as a union.

| Profile tag | Additional checks |
|-------------|-------------------|
| `check-profile-fast` | none |
| `check-profile-router` | `router-checks` |
| `check-profile-io-predeploy` | `predeploy-check` |
| `check-profile-io-final` | `final-checks`, `router-endpoints-checks`, `endpoints-manifest-check` |
| `check-profile-garage` | `garage-checks` |
| `check-profile-politikerstod` | `politikerstod-checks` |
| `check-profile-wireguard` | `wireguard-checks` |
| `check-profile-paperless` | `paperless-checks` |
| `check-profile-accounted` | `accounted-checks` |
| `check-profile-backups` | `backups-checks`, `backups-multi-checks`, `backups-failure-checks` |
| `check-profile-mailserver` | `mailserver-checks` |
| `check-profile-sedna` | `sedna-failover-checks` |

Always run preflight checks before deploying. Only use `--force` for recovery or when you're certain no validation is needed.

The command validates machine names before running checks; unknown names fail fast.
