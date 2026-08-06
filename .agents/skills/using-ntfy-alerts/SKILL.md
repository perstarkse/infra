---
name: using-ntfy-alerts
description: >-
  Publishes and diagnoses ntfy push alerts in this infra (topics, ACLs, curl
  publishers, storage/backup/indicator patterns). Use when adding ntfy
  notifications, changing topic ACLs, debugging empty topics, or wiring a
  service to ntfy.lan.stark.pub.
---

# Using ntfy Alerts

ntfy runs on **io** behind nginx. Publishers must use the HTTPS vhost, never the raw listen address.

| Item | Value |
|------|-------|
| Public URL | `https://ntfy.lan.stark.pub` |
| Host | `io` (`my.ntfy` in `machines/io/configuration.nix`) |
| Module | `modules/system/ntfy.nix` |
| Auth env | Clan vars `vars/generators/ntfy.nix` → `/run/secrets/vars/ntfy/env` |
| Storage token | `/run/secrets/vars/ntfy/storage-token` (shared secret, tag `ntfy`) |

**Never publish to `http://10.0.0.1:2586`.** The port is firewalled; curl hangs (exit 28). Always use `https://ntfy.lan.stark.pub/<topic>`.

## Canonical topics

| Topic | Who publishes | Auth to publish | Who may subscribe |
|-------|---------------|-----------------|-------------------|
| `storage-alerts` | `my.storage-alerts` (makemake) | Bearer token (`storage-publisher`) | Anonymous read |
| `backup-alerts` | `my.backupFailureNtfy` onFailure hooks | Anonymous write | Anonymous read+write |
| `indicator-alerts` | `indicator-alert-daemon` | Anonymous write | Anonymous read+write |

ACL is defined in `vars/generators/ntfy.nix` as `NTFY_AUTH_ACCESS` (deny-all default):

```text
storage-publisher:storage-alerts:wo,*:storage-alerts:ro,*:indicator-alerts:rw,*:backup-alerts:rw
```

After changing that generator or regenerating vars on io: **restart `ntfy-sh`**. Env file updates do not hot-reload into a running process. Verify with:

```bash
# on io
grep NTFY_AUTH_ACCESS /run/secrets/vars/ntfy/env
tr '\0' '\n' < /proc/$(systemctl show -p MainPID --value ntfy-sh)/environ | grep NTFY_AUTH_ACCESS
ntfy access
systemctl restart ntfy-sh   # if disk != process
```

## Existing publishers (reuse these)

### Storage alerts

- Module: `modules/system/storage-alerts.nix`
- Enable + mounts on the machine (see `machines/makemake/configuration.nix`)
- Token: `tokenFile = config.my.secrets.getPath "ntfy" "storage-token"`
- Behavior: healthcheck timer only curls on **state transitions** (problem appears / clears). Empty topic + successful timer = healthy, not broken.

```nix
my.storage-alerts = {
  enable = true;
  mounts = [ "/storage" ];
  ntfy = {
    serverUrl = "https://ntfy.lan.stark.pub";
    topic = "storage-alerts";
    tokenFile = config.my.secrets.getPath "ntfy" "storage-token";
    tags = [ "warning" "floppy_disk" "<hostname>" ];
  };
};
```

Machine must discover the `ntfy` secret tag and grant the healthcheck unit read access to `storage-token` if not already covered by shared vars mounts.

### Backup failure alerts

- Module: `modules/system/backups.nix` → `my.backupFailureNtfy`
- Fires only when a `restic-backups-*.service` fails (`onFailure`)

```nix
my.backupFailureNtfy = {
  enable = true;
  url = "https://ntfy.lan.stark.pub/backup-alerts";
};
```

### Indicator daemon

- Module: `modules/system/indicator-alert-daemon.nix`
- Default URL: `https://ntfy.lan.stark.pub/indicator-alerts` (anon write)

## Adding a new alert from a service

Prefer the smallest change:

1. **Reuse an existing topic** if the audience matches (storage / backups / indicators).
2. Otherwise add a topic + ACL entry in `vars/generators/ntfy.nix`, regenerate vars on io, restart `ntfy-sh`.
3. Publish with curl from a oneshot or `onFailure` unit.

### Curl publisher template (anonymous topic)

```nix
pkgs.writeShellScript "my-service-notify" ''
  set -euo pipefail
  ${pkgs.curl}/bin/curl -fsS \
    --retry 2 --retry-delay 2 \
    -H "Title: ${config.networking.hostName}: my-service failed" \
    -H "Priority: high" \
    -H "Tags: warning,${config.networking.hostName}" \
    --data-binary "$1" \
    https://ntfy.lan.stark.pub/<topic>
'';
```

### Curl publisher template (token topic)

```nix
# tokenFile = config.my.secrets.getPath "ntfy" "storage-token";  # or a new token
curl_args+=( -H "Authorization: Bearer $(<${tokenFile})" )
```

Wire with systemd:

```nix
systemd.services."my-service" = {
  onFailure = [ "my-service-notify.service" ];
};
systemd.services."my-service-notify" = {
  serviceConfig = {
    Type = "oneshot";
    ExecStart = "${notifier} \"details here\"";
  };
};
```

### New topic checklist

- [ ] Add `*:my-topic:rw` (or tighter) to `canonical_access` in `vars/generators/ntfy.nix`
- [ ] If write must be authenticated: add user/token like `storage-publisher` and grant `wo` / `rw`
- [ ] `clan vars generate` / deploy io so `/run/secrets/vars/ntfy/env` updates
- [ ] `systemctl restart ntfy-sh` on io
- [ ] Confirm `ntfy access` shows the new grants
- [ ] Probe publish + `?poll=1` subscribe (see below)
- [ ] Point the service at `https://ntfy.lan.stark.pub/my-topic`
- [ ] CHANGELOG under `### Changed` / `### Added`

## Diagnose empty topics

Empty ≠ broken. Check whether a publish was **attempted**.

### 1. ACL actually loaded?

```bash
ssh root@10.0.0.1 'ntfy access; systemctl show ntfy-sh -p ActiveEnterTimestamp'
# disk env must match process env (restart if not)
```

Expected anonymous grants after a good reload:

- `storage-alerts`: read-only
- `indicator-alerts`: read-write
- `backup-alerts`: read-write

### 2. Did the publisher run?

```bash
# makemake examples
journalctl -u storage-alerts-healthcheck.service --since '7 days ago'
ls /var/lib/storage-alerts   # empty dir => no open problems => no storage publishes
journalctl -u 'backup-failure-notify@*' --since '30 days ago'
systemctl show restic-backups-<job>.service -p OnFailure
journalctl -u 'restic-backups-*' -p err --since '14 days ago'
```

| Symptom | Meaning |
|---------|---------|
| Healthcheck always exit 0, empty state dir | No storage alert condition; topic should stay empty |
| `backup-failure-notify@*` exit 28 / timeout | Still hitting `10.0.0.1:2586` or network path broken |
| Notify unit never starts | Missing `onFailure` or restic never failed |
| Publish HTTP 403 | ACL missing for that topic/identity, or token wrong |
| Anon poll 403 on `*:ro`/`*:rw` topics | Process still on old ACL → restart `ntfy-sh` |

### 3. Probe publishes

```bash
# indicator / backup (anon write)
curl -fsS -d "probe-$(date +%s)" https://ntfy.lan.stark.pub/indicator-alerts
curl -fsS -d "probe-$(date +%s)" https://ntfy.lan.stark.pub/backup-alerts

# storage (token write) — run on a host that can read the secret
curl -fsS \
  -H "Authorization: Bearer $(</run/secrets/vars/ntfy/storage-token)" \
  -d "probe-$(date +%s)" \
  https://ntfy.lan.stark.pub/storage-alerts

# anon poll (should work for all three after ACL reload)
curl -fsS 'https://ntfy.lan.stark.pub/storage-alerts/json?poll=1&since=10m'
```

### 4. Server-side message cache

On io, ntfy stats log `messages_cached` / `messages_published`. Cache lives under `/var/lib/ntfy-sh/cache-file.db` (default retention ~12h).

## Phone / subscriber notes

- Subscribe to `https://ntfy.lan.stark.pub/<topic>` (LAN / WireGuard).
- `storage-alerts` is subscribe-only for anonymous clients; publishers must use the token.
- If the UI opens but never receives: almost always missing `*:topic:ro` (or process still on old write-only ACL).

## File map

| Path | Role |
|------|------|
| `modules/system/ntfy.nix` | Server + exposure |
| `vars/generators/ntfy.nix` | Users, tokens, ACL |
| `modules/system/storage-alerts.nix` | Token publisher + health checks |
| `modules/system/backups.nix` | `backupFailureNtfy` |
| `modules/system/indicator-alert-daemon.nix` | Indicator topic URL |
| `machines/io/configuration.nix` | Enables ntfy |
| `machines/makemake/configuration.nix` | Storage + backup + indicator consumers |
