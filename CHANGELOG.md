# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Fixed

- **sedna DNS failover false-triggering** (`machines/sedna/configuration.nix`): `heartbeatTimeoutMinutes` raised 5 → 10 (io's `*:0/5` push with the 2m randomized delay let healthy gaps reach ~7 min, exceeding the old timeout; 866 false "heartbeat lost" events/week, real DNS PATCHes flipping public domains to the maintenance page). io's `heartbeat.push.randomizedDelaySec` lowered 2m → 30s to shrink jitter.
- **ddclient never updating on io** (`modules/system/router/nginx.nix`): ddclient 4.x daemonizes by default — the oneshot units exited 0 in ~150ms doing nothing and left zombie daemons, so `nous.fyi` stayed pointed at sedna's maintenance page for 2 days after a failover flap. Units now run `--foreground` with a writable per-zone cache (`/var/lib/ddclient` via `StateDirectory`) and no `daemon=` line (4.x treats `daemon=0` as a 60s loop that never exits). Verified: records restored, both zones run clean, timers healthy.
- **`chat.stark.pub` ACME order failing daily on io** (`modules/system/openwebui.nix`): the LAN-only vhost got a per-vhost HTTP-01 order against no public A record (`no valid A records found`, system `degraded`). LAN-only openwebui vhosts now set `noAcme = true`; the failing unit is gone after rebuild.
- **charon `systemd-journal-upload` crash loop** (`machines/charon/configuration.nix`): a giant `COREDUMP_STACK_TRACE` from crashing QtWebEngine/garage processes (10 MB+ entries, rejected by nginx's body limit) wedged the uploader since Aug 3. `systemd.coredump.settings.Coredump.ProcessSizeMax = "512M"` caps future in-journal backtraces; uploads verified flowing to io's collector again (4313 charon entries received).
- **charon auto-suspend never firing** (`modules/system/auto-suspend.nix`): a Wayland idle-inhibiting app kept the session `IdleHint` stuck at `no`, so the seat never counted as idle. New `treatStaleIdleHintAsIdle` option (default true) treats a hint stuck past `userIdleSeconds` as idle; block-mode sleep inhibitors are still respected.
- **pg_dump artifacts inside restic snapshots** (`machines/makemake/configuration.nix`): `nous_prod.dump` / `paperless.dump` are written into the restic data dirs, embedding a redundant copy in every snapshot. Both jobs now exclude the dump path.
- **libvirt pool not autostarting** (`modules/system/libvirt.nix`): NixVirt 0.6.0 has no pool autostart support; a oneshot `libvirt-pool-autostart` service (after libvirtd) runs `virsh pool-autostart` for declared pools.

### Changed

- **io nginx runs more than one worker** (`modules/system/router/nginx.nix`): `prependConfig = "worker_processes auto;"` + `eventsConfig = "worker_connections 2048;"` (the `workerProcesses` NixOS option was removed in 26.05). ~19 vhosts were served by a single worker on the 4-core router; verified 4 workers after deploy.
- **Journal size bounds**: io `SystemMaxUse=512M` (was 4 GiB unbounded, kea/blocky noise), sedna `SystemMaxUse=256M` (was 1.8 GiB on a 46 GiB disk). Verified io at 512M bound post-rotation, sedna 226.9M and dropping.
- **Postgres tuning on makemake** (`modules/system/nous.nix`, `paperless.nix`, `politikerstod.nix`): all three servers ran stock 128 MB `shared_buffers` (0.7 % of 32 GiB). Now explicit modest budgets — nous 512MB/6GB cache/80 conns/32MB work_mem, container DBs 256MB/1GB/50/16MB — ≈ 1 GiB total added, no cgroup ballooning.
- **charon storage alerts enabled** (`machines/charon/configuration.nix`): `my.storage-alerts` with ntfy (`storage-alerts` topic); the 88 %-full root btrfs volume now fires the 85 % capacity warning (verified end-to-end ntfy publish).

### Changed

- **npm 7-day release-age gate for pi extensions and all global npm installs** (`modules/home/node.nix`): the managed `~/.npmrc` now sets `min-release-age=7`, so npm refuses any package published strictly more-recently than 7 days ago.

### Removed

- **Non-pi agent harnesses deprecated**: the `opencode` daemon service (systemd `opencode-daemon`, agent-tooling `nixosModules.opencode-daemon` export, `oc-attach`/`oc-omo-attach` fish functions), the `llm-agents` flake input + overlay (removed `pkgs.llm-agents`), the `llm-agents-cli` home module, and the now-abandoned CLI harnesses it installed (opencode, codex, claude-code, amp; ariel's `z-claude` launcher too). `agent-browser` is kept, re-homed to `pkgs.agent-browser` from nixpkgs on charon. The inert `sandboxed-binaries` home module and `sandboxed-binaries` import are gone; codex/sandbox references trimmed from sccache docs. `agent-microvm` is kept.

- Dead WM/display stack: `hyprland`, `sway`, `steam-gamescope` system modules, home `hyprland`/`sway` modules, and their flake inputs (`hyprland`, `hyprland-plugins`, `hy3`, `hyprnstack`, `sway-focus-flash`). `my.gui.session` is now niri-only; greetd and waybar branches trimmed.
- Dead infra/app modules and config blocks: `k3s`, `unifi-controller`, `minecraft` (+ `nix-minecraft` input + makemake berget-2 block), `minne` (+ input + generator), `codenomad` (+ `pkgs-update` script + `pkgs/codenomad`), `openchamber` (+ `pkgs/openchamber`), `vfio`, home `looking-glass-client`, `vars/generators/k3s-token.nix` and `minne-env.nix`.
- Orphaned artifacts: `wallpaper-1.jpg`/`wallpaper-2.jpg` (~6.7 MB), commented swaybg/wallpaper blocks, io `secrets.declarations = []`, commented tunnel/allowReadAccess/devenv blocks, stale hw-config comments.
- **IPv6 from the LAN**: router ULA/RA/PD advertisement, AAAA local-data, `[ula]::1` blocky listener, per-segment ip6 firewall rules, ip6 DoT upstreams, ULA64 nginx allow rules, `natV6` table, garage `s3_web` (port 3902), the IPv6 heartbeat URL normalization, and the IPv6-branch of the restricted-port firewall helper. `filterAaaa` stays on; the ip6 input table now only guards the router's own v6 (ZeroTier/link-local).
- `my.router.ipv6.ulaPrefix` option, router compat aliases (`lanSubnet`/`lanCidr`/`routerIp`/`lanInterface`/`lanPorts`), `routerAccessLevel = "full"` alias, and the unused `dnsFailover.ioPublicIp` option.
- kube-test.lan.stark.pub router entries on io (DNS service record + nginx vhost) — dead test-cluster vhost, nothing behind it.
- makemake `networking.firewall.allowedTCPPorts = [8088]` — no listener on 8088 (verified via `ss` on the live machine).
- machines/sedna heartbeat-receiver hardening override — moved into the heartbeat module (see Changed).

### Changed

- **invoices.stark.pub webhook declared on the service (split-horizon DNS)**: the Accounted invoice-inbox endpoint moved from a hand-written io-side `my.endpoints.services` block (with a manual `dns.records` target) into `my.accounted.invoiceWebhook` on makemake. io imports it like other makemake services, so the internal DNS record auto-derives to the router LAN IP (`10.0.0.1`) via `defaultDnsTarget`, the public record flows into the derived `my.publicDomains` registry, and the 444 webhook gating now lives with the service. The router needs a single `vhostOverrides."makemake.accounted-invoice"` DNS-01 ACME override (mirroring nous); nginx vhost is byte-equivalent (listens 0.0.0.0, proxy → 10.0.0.10:3050, strict public rate zone, `dnsProvider=cloudflare`). Router internal/DNS comment now uses the canonical **split-horizon DNS** term and documents the no-hairpin rationale (WAN-only DNAT + strict rp_filter in dns.nix/endpoints.nix).

- **Shared systemd hardening helper** (`mkHardenedServiceConfig` via `_module.args`, options.nix): the 16-line lockdown that sedna's heartbeat-receiver and failover-check duplicated is now one function; the heartbeat receiver's hardening moved into `heartbeat.nix` where the unit is defined (machine config no longer reaches into a module-owned unit). Effective service configs byte-identical (eval-verified).
- sedna-failover/revert scripts: the identical `--dry-run` parsing + token-loading preamble (~25 lines) is now one `scriptPreamble` string shared by both scripts; generated scripts unchanged (drill VM tests pass).

- **Machine configs trimmed of set-to-default and dead values** (review-driven): io drops ~80 lines restating router-module defaults (dhcp ranges/timers, dns upstreams/profiles, wan interface, fail2ban jail defaults, zerotier access level, casting segment, empty portForwards, default dns.profiles); makemake drops ~30 lines of service-option defaults (surrealdb, minne-saas, nous, vaultwarden, garage, attic-cache, supabase, accounted, accounted-ocr, openwebui schedule); charon/ariel drop gui/auto-suspend/powerManagement/wakeOnLan defaults and stale comments; sedna drops dead failover/heartbeat options and merges duplicate read-access grants; charon disko.nix loses commented-out disk blocks. No behavior change anywhere (each deletion verified against the module default).

- **"Exposure" renamed to "endpoints"** (`my.exposure` → `my.endpoints`, `<service>.exposure` → `<service>.endpoints`, `my.exposure.routerImports` → `my.endpoints.imports`, `mkStandardExposureOptions` → `mkStandardEndpointsOptions`, `mkRouterImportedExposures` → `mkRouterImportedEndpoints`, `mkExposureManifest` → `mkEndpointsManifest`, `exposure-manifest-check` → `endpoints-manifest-check`, `tests/router-exposure.nix` → `tests/router-endpoints.nix`). Naming is uniformly plural (`mkStandardEndpointsOptions`, `mkEndpointsManifest`, `mkImportedEndpoints`); the unused `_module.args.endpointName` is dropped. The external `private-infra` input (overseerr → request.stark.pub) is migrated to `my.endpoints` (input bumped to `032d6d3`), so the `my.exposure` alias module and `mkStandardExposureOptions` module-arg alias are removed; its SPA rate-limit exemption is now declared on the vhost instead of a router `vhostOverrides` override (the `rateLimit` override sentinel is removed).
- **Public-domain registry is derived, not maintained**: `my.publicDomains` is now a projection of the endpoints layer (every non-lanOnly vhost, zone-mapped by suffix) plus explicit non-vhost public records (`my.publicDnsRecords`: wg, mail, orebro.politikerstod). io's hand-maintained registry is deleted; a ddclient-scoped lint fails the build if the registry diverges from the derivation, and raw `services.nginx.virtualHosts` writes are confined to an escape hatch asserted to never listen on WAN. sedna reads io's derived registry instead of mirroring it.
- **Rate limits live on the vhost**: a per-vhost `rateLimit` option (`null` = SPA exemption, `"strict"` = shared public zone, `{rate, burst, nodelay}` = dedicated zone) replaces the router-level `rateLimits` map. minne/nous/politikerstod declare their exemptions in their modules; request (external private-infra module) via router `vhostOverrides.rateLimit`. invoices.stark.pub migrates into the endpoints layer (was a raw nginx vhost); the nous.fyi `/app/` → `/assets/app/` rewrite moves into the nous module.
- **Heartbeat now goes over the public internet**: io pushes to `http://130.61.55.4:18080/heartbeat` (sedna public IP, port opened in the OCI security list) instead of a ZeroTier IPv6 literal; sedna's receiver binds `0.0.0.0` and the `heartbeat` secret no longer carries a target URL.
- charon kernel pin moved from `builtins.getFlake` into the locked `nixpkgs-612` input (kernel 6.12.74, offline evals, flake.lock-tracked).
- paperless backups now write to both Garage and B2 (offsite copy; `restore.backend = "garage"`).
- OpenWebUI `autoUpdate = false` for the digest-pinned image (no more weekly no-op restart).
- ariel: dropped the dead wpa_supplicant/`generate-wpa-conf` path and broken `wifi-psk` generator — Wi-Fi is handled by NetworkManager.
- `subagentOverrides` on charon generated from one `lib.genAttrs` template instead of six copy-pasted blocks.
- Restricted-port firewall logic consolidated into one `mkRestrictedPortRules` helper (endpoints options, politikerstod DB proxy, charon 8504).
- unbound `num-threads` 1 → 2 on the router.
- Attic push failures are logged to `/var/log/attic-push.log` instead of silently swallowed; restic backup timers get `RandomizedDelaySec` jitter.
- Workstations charon + ariel stream journals to io's mTLS journal-remote so sshd fail2ban covers them.

### Added

- **Fleet-wide config consolidation** (review-driven): new `journal-upload` module replaces the byte-identical journald mTLS client block on ariel/charon/makemake (`my.journalUpload.enable`); shared defaults for `time.timeZone`, `secrets.discover.dir`/`generateManifest`, and the main-user `exposeUserSecrets`/`allowReadAccess` grants (in `shared.nix`); `my.stylix`/`my.interception-tools` default to enabled; heartbeat receiver `gatusPort` now derives from `remote-monitoring.webPort` so the deadman callback can't silently diverge.

- **Sedna failover drill** (`nix run .#failover-drill`): dry-run mode simulates heartbeat loss in the `sedna-failover` NixOS test harness and shows the exact Cloudflare API sequence (record lookups + would-be PATCH payloads) with zero PATCH requests and no `dns-state.json` mutation; `--broken-token` mode verifies a missing or invalid Cloudflare token fails loudly. The failover/revert scripts gained a `--dry-run` flag (read-only: GETs only, no state writes) and the health check passes it through.

- DigiKey MCP server (`digikey-mcp` flake input) wired into the charon pi-agent MCP config: product sourcing tools (search, details, pricing, substitutions, media, manufacturers, categories, plus a `build_fastadd_url` cart helper) via DigiKey API v4 two-legged OAuth. Default locale is digikey.se (`SE`/`sv`/`SEK`) — DigiKey has no cart API, so cart population goes through the site-specific FastAdd browser URL. Secrets via `vars/generators/digikey.nix` clan vars (`client_id`, `client_secret`).
- Charon pi-agent `digikey` MCP config extended for the MyLists API v1 tools (3-legged OAuth): `DIGIKEY_CALLBACK_URL=https://localhost:8139/digikey_callback` (must match the app's registered OAuth Callback URL; app also needs a MyLists subscription) and `DIGIKEY_TOKEN_STORE=/home/p/.local/state/digikey-mcp/tokens.json` (runtime consent state, mode 0600; a one-time `mylists_authorize` consent is required before list tools work).
- digikey-mcp `AGENTS.md` agent runbook (gateway connect via the `connect` key, the 60 s backoff, the consent flow — Cloudflare blocks automation, the account owner opens the URL in their own browser on charon — and list CRUD/secrets hygiene), plus MyLists response shapes fixed against the live API (bump to `6051fd7`).

### Fixed

- sedna failover: a missing Cloudflare token file now fails the health check loudly (non-zero exit) instead of exiting 0 silently, so a secret-provisioning failure can no longer disable DNS failover during an outage without any alert.

- Heartbeat receiver: timestamp file is now written atomically (temp file + rename) with a trailing newline, so concurrent pushes or a reader mid-write can never observe a torn/concatenated timestamp, and `cat` output is newline-terminated.
- Workstation journal forwarding (charon/ariel): a first-time catch-up upload exceeds journal-remote's ~770 MiB per-session cap (`413 Payload too large`) and crash-loops the uploader. Onboard new clients by seeding `/var/lib/systemd/journal-upload/state` with the journal-tail cursor so upload starts from live entries (E6 only needs real-time visibility).
- makemake restic: restore B2 passwords into `restic-*-default` (multi-backend rename had regenerated passwords against existing repos); nous prepare runs `pg_dump` as `nous`; surrealdb(+saas) use RocksDB file-level backup (drop unsupported `surreal export`); paperless Garage bucket `restic-makemake-paperless` granted to `charon-key`; garage-s3 restic bootstrap uses Garage admin CLI on Garage nodes instead of S3 CreateBucket.
- Router nginx: `rateLimits.<domain> = null` exempts a vhost from `limit_req`; the five JS-heavy public vhosts (`minne`, `chat`, `nous.fyi`, `politikerstod`, `request`) are now exempt — the previous 60 r/m zones serialized SPA page loads (~40 requests each) to ~1 req/s, producing 10 s+ page loads. Non-SPA tools keep the strict `public` zone (10 r/m, burst 20, nodelay); fail2ban still blunts scanners.
- `indicator-alert-daemon` flake import uses `nixosModules.default` instead of the removed root `module.nix` path (flake-parts migration).
- ntfy auth ACL now grants subscriber read on `storage-alerts`, `indicator-alerts`, and `backup-alerts` (previously write-only under `deny-all`, so phones could open the UI but never receive messages).
- makemake storage/backup ntfy publishers now use `https://ntfy.lan.stark.pub` instead of firewalled `http://10.0.0.1:2586` (backup-failure-notify was failing with curl exit 28).
- `wow-launcher` (umu desktop path): enable `umu-battlenet` protonfixes and stop forcing `PROTON_USE_WINED3D` by default so Battle.net Play can spawn `WowClassic.exe` (was logging `Could not launch … (FAILED)`). Steam's Proton package is unchanged.
- `wow-launcher`: drop the direct WoW Classic Anniversary desktop entry/CLI (skips Battle.net SSO; use Battle.net → Play).

- **UniFi OS container stuck in a stale "running" state after a deploy** (io `uosserver`, degraded system since Jul 31): a `clan machines update` that restarted `unifi-os-runtime.service` SIGKILLed the container after the default 90 s stop timeout, and conmon died before reporting the exit — so podman kept believing the container was Up while crun refused all execs, healthchecks failed every 60 s, and nothing recreated it. Two hardening changes in `modules/system/unifi-os.nix`: the runtime unit now stops the container via `ExecStop = podman stop --time 30` (the UniFi image ignores SIGTERM, so a plain unit stop always ends in SIGKILL; letting podman run the kill keeps the container state consistent — Exited, not a stale zombie — so the supervisor restarts it), and a new `unifi-os-recover` timer (every 5 min) detects the zombie state (health failing + main PID dead) and recreates the container via `unifi-os-prepare` + runtime restart as a safety net for any other path that kills conmon. Live recovery was done by removing the stale container (`podman rm -f uosserver`), re-running prepare, and restarting the runtime; the watchdog recovered the container on its own three times during validation and no-ops when healthy, the ExecStop restart test stopped the container cleanly in 30 s with no zombie, and `https://10.0.0.21/api/ping` returns 204.
- **Headless router getty flapping** (io): the privileged UniFi container shares the host `/dev/tty1` device node (4:1) and its systemd touches it during boot, killing the host agetty; upstream `Restart=always` then restarts it and a burst hits the start limit, leaving the getty failed and the system degraded. io now disables both `getty@tty1` and `autovt@tty1` (`systemd.services."getty@tty1".enable = false` / `"autovt@tty1".enable = false`) — SSH-only router, no console to lose.

### Added

- Self-hosted **Supabase + Accounted** on makemake (LAN-only):
  - `modules/system/supabase.nix` — pinned upstream Docker Compose stack, Clan-rendered `.env`, Garage S3 storage overlay, Garage key provision, logical `pg_dump` backups to garage-s3 + B2
  - `modules/system/accounted.nix` — pinned Accounted app+cron compose, migration ledger oneshot, LAN bind overlay
  - Domains: `accounting.lan.stark.pub`, `supabase.lan.stark.pub` (wildcard `lanstark`, router `io`)
  - Secrets generators `vars/generators/supabase.nix` + `accounted.nix` (HS256 JWT minting via openssl)
  - VM test `tests/accounted-system.nix` + `check-profile-accounted` on makemake
- makemake `indicator-alert-daemon` tickers (ETH-USD daily, ETH-USD weekly, BOTZ, SEKEUR=X) each gain an RSI overbought alert (`threshold = 70.0`, `direction = "above"`) alongside the existing RSI < 30 alerts.
- Home Manager `wow-launcher` module: `wow-launcher` CLI plus a Battle.net desktop entry via `umu-run` against the existing Steam Proton prefix (default compatdata `3077503121`), including a `kill` subcommand for stuck Agent processes after suspend. Enabled on charon.
