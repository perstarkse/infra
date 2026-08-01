# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added

- DigiKey MCP server (`digikey-mcp` flake input) wired into the charon pi-agent MCP config: product sourcing tools (search, details, pricing, substitutions, media, manufacturers, categories, plus a `build_fastadd_url` cart helper) via DigiKey API v4 two-legged OAuth. Default locale is digikey.se (`SE`/`sv`/`SEK`) — DigiKey has no cart API, so cart population goes through the site-specific FastAdd browser URL. Secrets via `vars/generators/digikey.nix` clan vars (`client_id`, `client_secret`).
- Charon pi-agent `digikey` MCP config extended for the MyLists API v1 tools (3-legged OAuth): `DIGIKEY_CALLBACK_URL=https://localhost:8139/digikey_callback` (must match the app's registered OAuth Callback URL; app also needs a MyLists subscription) and `DIGIKEY_TOKEN_STORE=/home/p/.local/state/digikey-mcp/tokens.json` (runtime consent state, mode 0600; a one-time `mylists_authorize` consent is required before list tools work).
- digikey-mcp `AGENTS.md` agent runbook (gateway connect via the `connect` key, the 60 s backoff, the consent flow — Cloudflare blocks automation, the account owner opens the URL in their own browser on charon — and list CRUD/secrets hygiene), plus MyLists response shapes fixed against the live API (bump to `6051fd7`).

### Fixed

- makemake restic: restore B2 passwords into `restic-*-default` (multi-backend rename had regenerated passwords against existing repos); nous prepare runs `pg_dump` as `nous`; surrealdb(+saas) use RocksDB file-level backup (drop unsupported `surreal export`); paperless Garage bucket `restic-makemake-paperless` granted to `charon-key`; garage-s3 restic bootstrap uses Garage admin CLI on Garage nodes instead of S3 CreateBucket.
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
