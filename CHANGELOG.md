# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Removed

- Dead WM/display stack: `hyprland`, `sway`, `steam-gamescope` system modules, home `hyprland`/`sway` modules, and their flake inputs (`hyprland`, `hyprland-plugins`, `hy3`, `hyprnstack`, `sway-focus-flash`). `my.gui.session` is now niri-only; greetd and waybar branches trimmed.
- Dead infra/app modules and config blocks: `k3s`, `unifi-controller`, `minecraft` (+ `nix-minecraft` input + makemake berget-2 block), `minne` (+ input + generator), `codenomad` (+ `pkgs-update` script + `pkgs/codenomad`), `openchamber` (+ `pkgs/openchamber`), `vfio`, home `looking-glass-client`, `vars/generators/k3s-token.nix` and `minne-env.nix`.
- Orphaned artifacts: `wallpaper-1.jpg`/`wallpaper-2.jpg` (~6.7 MB), commented swaybg/wallpaper blocks, io `secrets.declarations = []`, commented tunnel/allowReadAccess/devenv blocks, stale hw-config comments.
- **IPv6 from the LAN**: router ULA/RA/PD advertisement, AAAA local-data, `[ula]::1` blocky listener, per-segment ip6 firewall rules, ip6 DoT upstreams, ULA64 nginx allow rules, `natV6` table, garage `s3_web` (port 3902), the IPv6 heartbeat URL normalization, and the IPv6-branch of the restricted-port firewall helper. `filterAaaa` stays on; the ip6 input table now only guards the router's own v6 (ZeroTier/link-local).
- `my.router.ipv6.ulaPrefix` option, router compat aliases (`lanSubnet`/`lanCidr`/`routerIp`/`lanInterface`/`lanPorts`), `routerAccessLevel = "full"` alias, and the unused `dnsFailover.ioPublicIp` option.

### Changed

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

- DigiKey MCP server (`digikey-mcp` flake input) wired into the charon pi-agent MCP config: product sourcing tools (search, details, pricing, substitutions, media, manufacturers, categories, plus a `build_fastadd_url` cart helper) via DigiKey API v4 two-legged OAuth. Default locale is digikey.se (`SE`/`sv`/`SEK`) — DigiKey has no cart API, so cart population goes through the site-specific FastAdd browser URL. Secrets via `vars/generators/digikey.nix` clan vars (`client_id`, `client_secret`).
- Charon pi-agent `digikey` MCP config extended for the MyLists API v1 tools (3-legged OAuth): `DIGIKEY_CALLBACK_URL=https://localhost:8139/digikey_callback` (must match the app's registered OAuth Callback URL; app also needs a MyLists subscription) and `DIGIKEY_TOKEN_STORE=/home/p/.local/state/digikey-mcp/tokens.json` (runtime consent state, mode 0600; a one-time `mylists_authorize` consent is required before list tools work).
- digikey-mcp `AGENTS.md` agent runbook (gateway connect via the `connect` key, the 60 s backoff, the consent flow — Cloudflare blocks automation, the account owner opens the URL in their own browser on charon — and list CRUD/secrets hygiene), plus MyLists response shapes fixed against the live API (bump to `6051fd7`).

### Fixed

- Heartbeat receiver: timestamp file is now written atomically (temp file + rename) with a trailing newline, so concurrent pushes or a reader mid-write can never observe a torn/concatenated timestamp, and `cat` output is newline-terminated.
- Workstation journal forwarding (charon/ariel): a first-time catch-up upload exceeds journal-remote's ~770 MiB per-session cap (`413 Payload too large`) and crash-loops the uploader. Onboard new clients by seeding `/var/lib/systemd/journal-upload/state` with the journal-tail cursor so upload starts from live entries (E6 only needs real-time visibility).
- makemake restic: restore B2 passwords into `restic-*-default` (multi-backend rename had regenerated passwords against existing repos); nous prepare runs `pg_dump` as `nous`; surrealdb(+saas) use RocksDB file-level backup (drop unsupported `surreal export`); paperless Garage bucket `restic-makemake-paperless` granted to `charon-key`; garage-s3 restic bootstrap uses Garage admin CLI on Garage nodes instead of S3 CreateBucket.
- Router nginx: `rateLimits.<domain> = null` exempts a vhost from `limit_req`; the five JS-heavy public vhosts (`minne`, `chat`, `nous.fyi`, `politikerstod`, `request`) are now exempt — the previous 60 r/m zones serialized SPA page loads (~40 requests each) to ~1 req/s, producing 10 s+ page loads. Non-SPA tools keep the strict `public` zone (10 r/m, burst 20, nodelay); fail2ban still blunts scanners.
- `indicator-alert-daemon` flake import uses `nixosModules.default` instead of the removed root `module.nix` path (flake-parts migration).
- ntfy auth ACL now grants subscriber read on `storage-alerts`, `indicator-alerts`, and `backup-alerts` (previously write-only under `deny-all`, so phones could open the UI but never receive messages).
- makemake storage/backup ntfy publishers now use `https://ntfy.lan.stark.pub` instead of firewalled `http://10.0.0.1:2586` (backup-failure-notify was failing with curl exit 28).
- `wow-launcher` (umu desktop path): enable `umu-battlenet` protonfixes and stop forcing `PROTON_USE_WINED3D` by default so Battle.net Play can spawn `WowClassic.exe` (was logging `Could not launch … (FAILED)`). Steam's Proton package is unchanged.
- `wow-launcher`: drop the direct WoW Classic Anniversary desktop entry/CLI (skips Battle.net SSO; use Battle.net → Play).

### Added

- Self-hosted **Supabase + Accounted** on makemake (LAN-only):
  - `modules/system/supabase.nix` — pinned upstream Docker Compose stack, Clan-rendered `.env`, Garage S3 storage overlay, Garage key provision, logical `pg_dump` backups to garage-s3 + B2
  - `modules/system/accounted.nix` — pinned Accounted app+cron compose, migration ledger oneshot, LAN bind overlay
  - Domains: `accounting.lan.stark.pub`, `supabase.lan.stark.pub` (wildcard `lanstark`, router `io`)
  - Secrets generators `vars/generators/supabase.nix` + `accounted.nix` (HS256 JWT minting via openssl)
  - VM test `tests/accounted-system.nix` + `check-profile-accounted` on makemake
- makemake `indicator-alert-daemon` tickers (ETH-USD daily, ETH-USD weekly, BOTZ, SEKEUR=X) each gain an RSI overbought alert (`threshold = 70.0`, `direction = "above"`) alongside the existing RSI < 30 alerts.
- Home Manager `wow-launcher` module: `wow-launcher` CLI plus a Battle.net desktop entry via `umu-run` against the existing Steam Proton prefix (default compatdata `3077503121`), including a `kill` subcommand for stuck Agent processes after suspend. Enabled on charon.
