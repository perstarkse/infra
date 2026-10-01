# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added

- **Personal agent: commandcode provider, signal-cli 0.14.8, and the SSH installer fixes** — completing the agent work committed in `2102e90`:
  - the agent now runs on **commandcode** instead of OpenRouter: `customProvider`/`baseUrl`/`modelProvider` register it as a native OpenAI-compatible provider (Hermes supports these in `providers:`; no plugin), on `meta/muse-spark-1.3-contributor` with `agent.reasoning_effort: high` and `model_overrides` supplying the real 1M context window. Two shapes that silently do nothing: `model.default` must be the **bare** model id (Hermes does not split a `provider/model` pair out of it — `custom:name/model` ships `name/model` on the wire and the endpoint answers `400 … is not a valid model ID`), and `reasoning_effort` is not a provider key (`_KNOWN_PROVIDER_KEYS`), so it belongs under `agent:` or it is dropped with a warning.
  - `credentialEnvVar` points the provider at the credential already present in the env file as `COMMANDCODE_API_KEY`, instead of renaming a secret to match Hermes' derived `HERMES_CUSTOM_COMMANDCODE_API_KEY`.
  - `pkgs/signal-cli`: the release package at **0.14.8**, because nixos-26.05 ships 0.14.2 and device linking fails on it with `Link request error: StatusCode: 409` (AsamK/signal-cli#1556, #1709; bbernhard/signal-cli-rest-api#457, #591 — all resolved upstream by moving to a newer signal-cli). Needs `jdk25_headless`: its classes are class-file version 69. `my.signal-cli.package` defaults to it and falls back to `pkgs.signal-cli` on one line.
  - `agent-ssh-access`: the account has **no home** (`/var/empty/agent`, `createHome = false`), so it cannot write `~/.ssh/authorized_keys` at all. Chowning a managed home does not work — the NixOS `users-groups` activation chowns it back on every switch, and tmpfiles rules only run at boot.
  - `install-agent-authorized-key` lost `RemainAfterExit`: a path unit activates with `systemctl start`, and starting an already-active oneshot is a no-op, so the installer ran exactly once (before the key existed) and ignored every trigger since.
  - `signal-cli` gets an eval-time assertion that the `hermes-env` ACL entry lists `signal-cli` as a reader. `my.secrets` builds ONE ACL unit per path, so a second entry for the same file from another module loses silently — which is why the daemon could not read the account number and crash-looped.

- **charon: second account with GNOME, GDM, and two live sessions** — the machine had a single seat, one session and one greeter, so a second person could not log in without ending the running session:

  - `modules/system/session-dispatch.nix` — one greeter session (`charon`) that maps username → desktop. Needed because nixpkgs implements `services.displayManager.defaultSession` for GDM by running `set-session` in `display-manager`'s preStart, and that script calls `user.set_session()` for **every** normal user (`nixos/modules/services/x11/display-managers/set-session.py`): one global session name means every account gets the same desktop and it overrides whatever the greeter remembered. The dispatcher is the one place the per-user mapping lives, and it exports `XDG_CURRENT_DESKTOP` so each session still picks up its own portal config.
  - `services.displayManager.gdm.enable` on charon, replacing greetd (`modules/system/greetd.nix` stays for ariel). greetd runs one greeter session at a time; GDM starts an extra greeter on a spare VT and keeps the running session alive on its own VT (logind hands the single DRM master to whichever session is on the active VT). `autoLogin` for the main account replaces greetd's `initial_session`, so boot behaviour is unchanged.
  - Handover keybind `Mod+Shift+U` → `switch-user-greeter` → `org.gnome.DisplayManager.LocalDisplayFactory.CreateTransientDisplay` (gdm-50.1 `common/gdm-common.c` `goto_login_session` → `create_transient_display`, and `daemon/gdm-local-display-factory.xml`). Plain `Ctrl+Alt+F1` returns to the niri session. GDM ships **no** `switch-to-greeter` D-Bus method and no CLI in 50.1 (`daemon/gdm-manager.xml` exposes only RegisterDisplay/RegisterSession/OpenSession/OpenReauthenticationChannel; `daemon/meson.build` installs only `gdm`, `gdm-session-worker`, `gdm-wayland-session`, `gdm-x-session`), so gnome-shell's Switch User has to go through libgdm.
  - `security.polkit.extraConfig`: that method is `auth_admin` for every caller class (gdm-50.1 `data/org.gnome.displaymanager.policy`), which from a bare niri session would need a polkit agent plus a password prompt. The main account gets `yes`, only for `subject.local && subject.active`; the second user still authenticates at the greeter. `security.polkit.addRules` no longer exists in nixpkgs 26.05.
  - `services.desktopManager.gnome.enable` on charon. Its service pile (GNOME Online Accounts, evolution-data-server, power-profiles-daemon, bolt, tracker/localsearch, tinysparql, udisks2, upower, ibus) is all `mkDefault`, so nothing collides with the networkd setup in `shared.nix` or with `networkmanager.enable = false`; `services.gnome.gcr-ssh-agent` loses to the `mkForce false` in `modules/system/niri.nix`.
  - Second account `a` (uid 1001, groups video/input/bluetooth, no wheel/kvm/libvirtd/docker) via the `user-a` **clan users service** instance in `flake/parts/clan.nix`, scoped `machines = { charon = {}; }`. That service owns the account, its groups and its `hashedPasswordFile`, and its `user-password-<name>` generator is machine-scoped (`share = false`), so a fleet-wide `clan vars generate` prompts for it on charon and nowhere else. Leave the prompt empty and the service generates an xkcdpass password itself; read it with `clan vars get charon user-password-a/user-password`. Its Home Manager list is deliberately short — browsers, Thunderbird, bitwarden-desktop, kitty, fish, xdg helpers — with no `sops`/`mail-clients` (those carry an age `keyFile` it has no fleet secrets for). `org.gnome.desktop.screensaver` idle-activation and lock-enabled are set explicitly instead of inherited from GNOME's schema defaults, because the main account's lock is a Noctalia keybinding rather than an idle trigger. Not importing the niri home module is also what keeps a niri config and its 4s niri IPC wait out of that activation: the module gates on the system-wide `my.gui.session`, not on anything per user.
  - `vars/generators/secondary-user-password.nix` was **not** kept: every generator in this repo's `vars/generators/` carries `share = true`, and a generator with neither `share` nor a machine assignment is offered on *every* machine — an unscoped one made `clan vars generate` prompt for ariel as well. The clan users service is the machine-scoped mechanism this repo already uses for interactive accounts (`user-p`, charon + ariel).
  - **Not covered: her GNOME session's network applet.** This host is networkd-only, so GNOME has no NetworkManager to read state from; browsers, mail and nix are unaffected, but expect a wrong-looking connectivity indicator until it is checked on real hardware.
  - **Operating notes found on the first real deploy (charon, both accounts logged in):**
    - *A display-manager swap on a live machine can strand the outgoing session.* greetd's session child survived the greetd → GDM switch as an orphan (its logind session was closed, but niri and its user units kept running under the lingering user manager). `niri-session` refuses to start when `systemctl --user is-active niri.service` is true, so every login attempt for the main account exited 1 and GDM bounced straight back to the greeter — which reads exactly like a wrong password. `gnome-session` has no such guard, so the second account was unaffected. Recovery after any DM swap: `systemctl --user stop niri.service` (plus the orphaned bar/idle helpers), or reboot. Deliberately *not* automated in the dispatcher: the handover path intentionally keeps the main account's niri alive on its own VT, so an automatic kill would fire exactly where it must not.
    - *VT 1 is the greeter's VT and always authenticates; the other VTs are plain session switches.* With the main account's niri on tty3 and the GNOME session on tty2, `Ctrl+Alt+F1` reaches GDM's greeter (which then activates the already-running niri session instead of starting a second one), while `Ctrl+Alt+F2` / `Ctrl+Alt+F3` switch straight into a live session with no prompt. Switch to the VT that actually holds the session; read it from `loginctl list-sessions` (TTY column) after a boot, because the numbers are not fixed.
    - *`gdm.service` is masked on purpose.* nixpkgs' GDM module sets `systemd.services.gdm.enable = false` and runs the daemon through `services.displayManager.generic`, so the live unit is `display-manager.service`. `systemctl is-enabled gdm` returning `masked` is not a fault.

- **Personal agent: Hermes Agent on makemake + fleet-wide non-sudo agent SSH** — an always-on agent reachable over chat, running in container mode so it can `apt`/`pip`/`npm` install into a persistent environment:
  - `hermes-agent` flake input pinned to rev `ea114c3e98c3339e13004adfc6098cf28ed7d754` (upstream calls Nix a Tier 2, best-effort platform and the Python lock is tied to one interpreter family, so main is not tracked). Verified to evaluate *and build* against this repo's `nixos-26.05` (`services.hermes-agent.package` is realised in makemake's closure).
  - `modules/system/hermes.nix` — fleet wrapper over upstream's `nixosModules.default`: container mode + docker backend (makemake's `my.docker.enable` already claims `virtualisation.docker.enable`, which collides with upstream's podman-backend `mkDefault`), `stateDir` on RAID1 xfs rather than mergerfs `/storage` (the session DB is SQLite), `workingDirectory` pinned inside `stateDir` so one restic job covers everything, the gateway API port gated to io (container mode runs `--network=host`), and `approvals.deny` for sudo/force-push/disk-write/pipe-to-shell on top of `approvals.mode: smart` with `cron_mode`/`single_query_mode`/`unattended_mode: deny`. Channels only — `backend.mode` (web dashboard/Desktop) is unsupported in container mode.
  - `modules/system/agent-ssh-access.nix` — unprivileged `agent` account on charon, io, makemake and ariel: not in `wheel`, `docker` or `libvirtd`; only `systemd-journal` for log reads; key-only login (`password = "*"`). The authorized_keys line is assembled at activation from the generator's public half (clan vars are deploy-time only, so nixpkgs' build-time `authorizedKeys.keyFiles` cannot read it) with sshd's `restrict` option, which denies forwarding, PTY allocation and `~/.ssh/rc`. Relax per-host via `my.agent-ssh-access.authorizedKeysOptions`; a forced-command allowlist is deliberately not implemented yet.
  - `vars/generators/agent-ssh-key.nix` (fleet-wide ed25519 pair, public half always derived from the private half so the two cannot drift) and `vars/generators/hermes-env.nix` (KEY=VALUE provider + channel credentials). The private key reaches the agent through `my.secrets.exposeUserSecrets` into `/var/lib/hermes/home/.ssh/id_ed25519`; a GitHub known_hosts ships alongside it so `restrict`ed key auth is non-interactive.
  - restic job `hermes` on makemake: `.env` excluded (regenerated from the generator on every activation — keys never enter a backup repo) and a `sqlite3 .backup` prepare step, matching the existing `pg_dump` prep for nous/paperless/politikerstod, because a raw restic copy of the live SQLite session DB can be torn.
  - `SOUL.md` states the non-sudo boundary, the "no outward-facing action without an explicit go-ahead" rule, and that homelab facts belong in the `homelab` repo rather than only in conversation.
  - `hermes-env` rotation now restarts the gateway: upstream's module ships no `systemd.paths`/`restartTriggers` at all, and the unit is byte-identical across content rotations, so `my.secrets.mkTryRestartOnRotation` supplies the watcher (same pattern as ntfy-sh and gatus).
  - `modules/system/signal-cli.nix` + `my.signal-cli` on makemake — the Signal side of the agent. signal-cli is not in apt or snap and needs a JVM, so the host is the cheap place for it; the agent's container shares the host network namespace, so `SIGNAL_HTTP_URL=http://127.0.0.1:8080` reaches it with no port publishing. The account number is **not** a Nix option: the unit reads `SIGNAL_ACCOUNT` from the `hermes-env` secret at start, so the number never enters the flake, the git tree or the `/nix/store`, and the daemon and the agent cannot drift apart (Hermes requires the same variable in the same file). Values that are not strict E.164 fail the unit closed without echoing the number into the journal, which this host ships to the router. Hardening comes from the fleet helper with `MemoryDenyWriteExecute = false` (a JVM JITs its own bytecode and mmaps it W+X, so the default would kill the daemon at startup) and `StateDirectory=signal-cli` at 0700 for the linked-device credentials, plus `--scrub-log`. signal-cli's HTTP interface has **no authentication of any kind**, so the port is restricted to io and bound loopback-only; the blast radius is "act as the Signal account", not account theft.

- **Off-LAN alert relay + backup deadmen + boot barrier (next-targets #1,2,4,5)** — joint pi+agy implementation, see `.agent/reviews/next-targets.md`:
  - sedna runs `my.ntfy` behind `ntfy.stark.pub` (direct-A 130.61.55.4, DNS-only; explicit nginx vhost reusing the `*.stark.pub` DNS-01 wildcard; fail2ban `ntfy` jail on `ntfy-sh.service`); ntfy generator gains a gated `phone-token` (`phone-subscriber:ro`, anonymous read stays closed) for the phone with no VPN.
  - one shared `flake/lib/alert-fanout.nix` publisher (LAN 3s → WAN 5s, warn-only) replaces the three drifted curl blocks; `fallbackUrl`/`fallbackServerUrl` added on backupFailureNtfy, storage-alerts, heartbeat failureNtfy.
  - backup coverage: `accounted` (file-level), `politikerstod-lekeberg` (`pg_dump` in prepare, mirroring nous), `unifi` on io (`/var/lib/unifi-os`, live-mongo caveat); restic timers gain `Persistent=true`.
  - freshness deadman: restic units ping sedna's heartbeat receiver (`POST /heartbeat?job=<name>`, same WAN bearer, IP-literal, CA-pinned, warn-only `ExecStartPost`); receiver routes `?job=` to Gatus `backups_backup-<job>` (36h, email) without touching the failover timestamp; endpoint list is the `flake.lib.backupJobs` constant (no cross-machine eval); makemake + io provision `heartbeat`/`heartbeat-tls` secrets, workstations auto-opt-out.
  - `garage-ready.service` barrier (30s `garage status` probe) gates provisioners/bootstrap/FUSE mounts; `replicationMode` accepts `"none"`; apps stay on `Restart=` backoff.
  - sedna eval-decoupled via `flake.lib.publicDomains` (proven: sedna evals with io's config deliberately broken); `.agent/project.json` gains a `mid` tier; `docs/drill-log.md` template added.
  - DNS to create: `ntfy.stark.pub → 130.61.55.4` (DNS-only, unproxied). Phone onboarding: ntfy app → `https://ntfy.stark.pub`, user `phone-subscriber` + phone-password (`clan vars get sedna ntfy/phone-password`; the stock iOS app has username/password login only, no token field — phone-token stays the Bearer credential for API clients), subscribe storage-alerts/backup-alerts/indicator-alerts/heartbeat, verify on cellular.

### Changed

- **charon: default pi model → `meta/muse-spark-1.3-contributor` (high thinking)** — `machines/charon/configuration.nix` sets `defaultModel` plus all `subagentOverrides` models (scout/context-builder/planner/researcher/reviewer/delegate) to the Muse Spark 1.3 contributor model on the `commandcode` provider. The module default `defaultThinkingLevel` is already `high`, so no thinking override was needed. `defaultProvider` stays `commandcode` (unchanged).

- **Sibling flake inputs now fetched over `git+ssh`** — `agent-microvm` and `digikey-mcp` moved from `git+file:///home/p/repos/*` to private GitHub mirrors, so the lockfile no longer bakes local dirty state into narHashes and fresh clones evaluate with only documented SSH access. Prerequisites table added to README.

### Fixed

- **Personal agent: defects found in review, before any deploy** — an independent review pass over the staged agent work found problems that would have broken the first deployment. None of it had been deployed, so all of it was configuration-only fixes:
  - `signal-cli` bound `127.0.0.1:8080`, which is the same port `openwebui` already holds in makemake's host network namespace (`--network=host`) — the second binder loses the race at boot. Moved to 8085 and documented why.
  - Rotating `hermes-env` restarted the gateway but the container re-read the **stale** `.env`: upstream merges `environmentFiles` only in a system activation script (`nixosModules.nix:455`), never in the container's preStart. `hermes.nix` now re-renders `.env` and then try-restarts BOTH consumers of the secret (the gateway and the signal-cli daemon), so the two can never run on different account numbers.
  - The restic `backupPrepareCommand` ran `sqlite3 <missing.db> ".backup …"`, which **exits 0 and creates the source file**: a restic run before the agent's first launch would have left a 0-byte root-owned `state.db` that the `hermes` user then cannot open. Guarded with `[ -f ]` (verified: no file created when absent, consistent copy when present). The live `state.db*` is deliberately not excluded from the snapshot, since `.restic-prep/state.db` in the same snapshot is the consistent copy and excluding the live one would lose every session on early restores.
  - The agent owned the `authorized_keys` that constrained it, so `sed -i 's/^restrict //'` would have re-enabled port forwarding on the next login. The key is now installed root-owned 0444 into `/etc/ssh/authorized_keys.d/agent`, and the agent's home is root-owned and non-writable so it cannot create `~/.ssh/authorized_keys` either (sshd reads both paths and `authorizedKeysInHomedir` is global-only). Writable scratch moved to `my.agent-ssh-access.workDir`.
  - `install-agent-authorized-key` exited 1 on a boot before the secret was deployed, leaving the system degraded. It now exits 0 and lets the path unit install the key when it lands.
  - `/home/p` is 0700, so the agent could not reach `/home/p/repos` at all — requirement "read the infra/homelab repos" was silently broken. `traversePaths`/`readablePaths` grant `--x` on the home and `r-x` on the repos via setfacl, without changing the owner's own directory mode.
  - `known_hosts` was written to host `/etc/hermes`, which is not mounted into the container and is not a path OpenSSH reads; git-over-SSH would have failed host-key checks. Now installed into the agent's own `$HOME/.ssh` with github + all three fleet host keys.
  - `signal-cli` ran as root despite exposing an unauthenticated HTTP surface. Now a dedicated `signal-cli` system user.
  - `sudo *` in `approvals.deny` blocked the `apt`/`pip`/`npm` self-modification that container mode was chosen for, while adding nothing real (the fleet `agent` account holds no sudo rule). Removed, with the reasoning recorded.
  - `ssh-keygen -y` already emits the key's comment and a trailing newline, so the generator's `printf ' agent-ops'` produced a two-line "public key" and a doubled comment downstream. Removed.
  - Dropped a redundant `/nix/store` bind mount (upstream already mounts it) and added `agent-ssh-key` to makemake's `requireGenerators`.

- **ntfy env restored after malformed regeneration; generator fails closed now** — the 2026-09-21 regeneration (new phone-token/phone-password files) ran the script against a fresh-empty `$out` where the `PREV_ENV` parse-back could never fire (it also quoted the path as literal `"…"` characters), minted all tokens fresh, and wrote a users line with a role-less `phone-subscriber` entry plus token entries folded in and no `NTFY_AUTH_TOKENS` line — sedna `ntfy-sh` exited 1 (`invalid auth-users … expected format: 'name:hash:role'`) on the next deploy. Live store restored to the working generation (all four publisher tokens byte-identical to deployed consumers; phone hash bcrypt-verified against the stored phone-password). The generator drops the dead parse-back, documents the re-key-on-regenerate semantics, and validates the assembled env at generate time (one USERS line, one TOKENS line, every entry exactly 3 colon parts, exit 1 otherwise).

- **io degraded: stale `grafana` secret reader removed** (`machines/io/configuration.nix`) — the `allowReadAccess` entry granted the grafana `secret_key` to a `grafana` user that exists on no machine, so the generated `setfacl` unit failed with `Invalid argument` into `start-limit-hit` (io sat at `degraded` since Sep 13). No grafana runs anywhere, so the block was deleted outright.

- **makemake restic: `nous_prod.dump` / `paperless.dump` are actually snapshotted again** — since Aug 6 both dumps were written into the restic source dir, then excluded from the snapshot, then deleted: the DBs had zero backup coverage (found via the paperless users/extinction investigation; document files were always covered). Dropped both `exclude` lines (`machines/makemake/configuration.nix`). The old rationale was wrong on both counts: prepare runs to completion before restic scans in the same unit (no mid-write race), and restic chunk-dedups an unchanged dump to ~0 bytes per snapshot. Pre–Aug-06 snapshots may still hold older dumps (check `restic find paperless.dump` before they age out of retention).

- **charon: few-seconds freeze after resume with display already shown** —
  sda (`INTEL SSDSC2KB038TZ`, backing `/mnt/sdb`) enters standby on its own
  (~42x this boot, 3–4s per wake) and on every suspend (`STANDBY IMMEDIATE`
  even times out after 5s). The swapfile (2+GB used, priority 10 above zram)
  lives there, so the first post-resume page faults stall while the desktop
  is already visible. `machines/charon/configuration.nix` now disables the
  drive's internal standby timer (`hdparm -S 0 -B 255` on the stable
  `/dev/disk/by-id` path) via a boot oneshot plus `powerManagement.resumeCommands`
  (the drive resets to defaults on power cycle). Monitor path untouched —
  `monitor-power-resume` already runs `--no-block` and finishes in ~3s in
  parallel. Deploy charon, then confirm no new `Entering standby` for sda in
  `journalctl -k` across a suspend cycle.

- **`nous.fyi/app` returned 404** (`modules/system/nous.nix`): the router-side
  rewrite that maps the SPA onto Loco's `/assets/app/*` mount only matched
  `/app/` with the trailing slash, but the landing page CTA links bare `/app`,
  so nginx proxied it through untouched and `loco.rs` answered 404. Added
  `rewrite ^/app$ /app/ permanent;` ahead of the asset rewrite. Verified with
  the store nginx against the generated location block (`/app` → 301 `/app/`,
  `/app/` → 200, `/app/assets/*` → 200); io and makemake toplevels still eval.

### Added

- **charon: air-exhaust fan status at the left edge of the Noctalia bar** — new
  `infra/air-exhaust-status` plugin (`modules/home/noctalia/plugins/air-exhaust-status/`)
  streams `air-exhaust/fan/status` via `mosquitto_sub` and shows `<duty>% · <room>°C`
  leftmost in `bar.main` (before `sysmon`), with `stale`/`offline` coloring and no
  click actions. It authenticates as the new read-only `charon-ro` MQTT user
  (`read air-exhaust/fan/status` only, `modules/system/mosquitto.nix`), whose
  password is exposed to user `p` at `~/.config/air-exhaust/mqtt.env` and gated
  behind `my.noctalia.airExhaust.enable` (on for charon only). The credential
  generator lives in `vars/generators/air-exhaust-mqtt.nix` (shared values,
  discovered by tag on io and charon) with `charon-ro.env` scoped
  `neededFor = "users"` — an io-local declaration never reaches charon's
  secret inventory, so a shared discovered generator is required. Deploy needs
  one `clan vars generate` for the two new `charon-ro.*` secret files, then
  update io (broker ACLs) and charon.

- **MQTT credential rotation broke all air-exhaust consumers (2026-09-08)** —
  adding `charon-ro.*` files re-ran the `air-exhaust-mqtt` generator script,
  which regenerates *every* password in the generator, not just the missing
  files. io picked up new hashes while the ESP32 firmware (compiled-in creds),
  Home Assistant (`hass`), and charon held mismatched generations, so the
  broker refuses all of them (`Connection Refused: not authorised`, incl.
  `nix run .#air-exhaust-broker-log`). Recovery is convergence, not rotation:
  update io + charon from the current store *without* `clan vars generate`,
  then refresh `printing/.../firmware/.env` from the store `air-exhaust.env`
  and reflash (OTA/USB), then update HA's mqtt password. Known footgun: any
  future file added to this generator rotates all sibling passwords the same
  way — splitting `charon-ro` into its own generator would isolate that.
  Resolution found during triage: the 09:36 update deployed the new hashes
  but the unit file was byte-identical (same secret paths/ACLs), so nothing
  restarted mosquitto — it kept serving the pre-rotation hashes assembled at
  09:21. A manual `systemctl restart mosquitto` on io picked up the current
  credentials (auth verified from charon right after). Secret-content-only
  changes do not bounce this service; any future credential rotation needs an
  explicit broker restart (or a `restartUnits` wiring) to take effect.
  HA repaired 2026-09-08 ~10:00: backup + stop `podman-homeassistant`, patch
  the `mqtt` entry's `password` in `.storage/core.config_entries` from the
  store `hass.env` (jq, perms preserved via `chmod --reference`), restart —
  broker log shows `hass` connected. Backup left at
  `core.config_entries.bak-20260908` on io; frigate has mqtt disabled, so it
  was unaffected.

- **charon: tether Bluetooth notifications now reachable** — `my.tether.experimentalBluetoothd`
  runs bluetoothd with `--experimental` so BlueZ exposes the per-transport
  `org.bluez.Bearer.LE1` interface. NixOS's bluetooth module has no flag option
  (it builds ExecStart from a hardcoded args list), so the tether module now
  overrides bluetooth.service ExecStart (`mkForce`) to append the flag; the
  upstream `bluetooth-experimental.conf` drop-in pointed at `/usr/lib` paths
  that don't exist on NixOS and was previously skipped. The flag must be active
  BEFORE pairing — a bond made without it has no LE half and ANCS notification
  mirroring can never come up. `tether --bt-setup` now reports nothing to do
  (was: "1 step left", because the class fix was already declarative via
  `tether-btclass@hci0` but the Bearer API step was still missing).

### Added

- **sedna failover/revert now announces itself** — the unit that rewrites public DNS had no notify hook: the only signal was the Gatus deadman, which reports a *different* fact ("io heartbeat missing") over a path correlated with the failure it reports. `modules/system/sedna-failover.nix` now emits a notice on state TRANSITION only (never per timer tick): `failover engaged` (naming the domains now pointing at sedna), `revert complete`, and `revert INCOMPLETE` (naming the domains still stuck — the case that hides). Delivery reuses the one path proven to survive both io and makemake dying: the backup-MX smtp2go credentials (`my.sedna-failover.dnsFailover.alertEnvFile`, set to the `gatus` env on sedna). Notice delivery is deliberately non-fatal — the PATCH already landed, so a dead SMTP path must not abort or mask an operation that already changed production DNS — and the attempt is logged with its subject first, so a delivery failure still names what it was reporting. Tests: `sedna-failover-dns-check` and `sedna-failover-revert-partial` assert the notice is attempted on both transitions and that delivery failure warns without failing the operation.

- **secrets rotation now bounces every long-running consumer, is verified by a VM test, and fails closed on undiscovered generators** — `systemd.path` watchers on the real secret files restart/reload the services that read them only at startup (garage, vaultwarden, nous, surrealdb, minne-saas, supabase, paperless, accounted, politikerstod, webdav-garage, rclone-s3, atticd, journal-upload, gatus, grafana, ntfy, heartbeat receiver, wireguard tunnels, mosquitto, makemake's indicator daemon). `restartTriggers` on `/run/secrets` paths are inert strings, so none of this was wired before. Restarts use `try-restart` (converge if running, no-op if stopped — a hard `restart` fails the watcher when the target cannot come up and strands the rotation); oneshot render services keep `restart` because a finished oneshot must re-run. New `nix build path:.#secrets-rotation-checks` VM test rotates the mosquitto hashes on disk and asserts the broker converges with no manual step; `nix build path:.#rotation-wiring-checks` is a table-driven harness asserting the target service actually restarts and stays healthy after its secret rotates (mosquitto, ntfy, garage today — one table row per new watcher). New `lib/secrets-discovery-check.py` (in `checks`, `nix build path:.#checks.x86_64-linux.secretsDiscoveryCheck`) fails the build when a generator's tags are discovered by no machine — the silent "secret deploys nowhere" class from the air-exhaust incident. Operational runbooks (escrow inventory, MQTT consumer convergence order) are kept local-only outside this public repo.

### Fixed

- **secrets rotation is honest now: mosquitto bounces on hash change, generator guards corrected** — `modules/system/mosquitto.nix`: the old `restartTriggers` on `/run/secrets/...` paths was inert (unit derivation never changes on content rotation, so nothing restarted the broker after a password change). Replaced with a `systemd.path` watcher that restarts mosquitto whenever a password hash actually changes on disk. `vars/generators/{heartbeat-tls,air-exhaust-mqtt,db-passwords}.nix`: removed `$out`-existence guards that could never fire (clan always executes generator scripts with a fresh empty `$out`) and replaced the false "idempotent" comments with the true rule — any execution regenerates all files, so never add a file to an occupied generator unless rotating its siblings is the intent. Standing policy agreed: rotation is manual and scoped (expiry — heartbeat server cert expires 11/2028 — compromise, rebuild); gap-fill generation stays automatic. SKILL.md `neededFor` guidance corrected (`services` vs `users` were swapped).

- **kea reservation `exhaust-c6` held the wrong MAC** (`machines/io/configuration.nix`):
  `44:1b:f6:d6:27:30` @ 10.0.0.101 is a different, unidentified ESP32 —
  every OTA post and `OTA_HOST` hit it instead of the controller.
  Reservation MAC corrected to the real C6 (`9c:cc:01:43:a2:f8`, esptool
  2026-09-04); redeploy io and let the C6 renew DHCP (or power-cycle it).
- **politikerstod: `uvloop` 0.22.0 `test_cancel_post_init` flake on Python 3.13** — `machine-update` for charon/makemake runs `politikerstod-checks` (VM test) which pulled `python3.13-uvloop-0.22.0` via the pinned `nixpkgs` (2026-01-21). That version flakes on `test_cancel_post_init` (`unexpected calls to loop.call_exception_handler()`), fixed upstream in 0.22.1 by disabling the test. Patched `politikerstod/nix/modules/context.nix` to set `python313Packages.uvloop.doInstallCheck = false` (narrow, drop when pin moves past 0.22.1) and bumped `flake.lock:politikerstod` to `6f7dc11`.

- **charon: pre-existing `auto-suspend-resume-hooks` VM test failing** — the
  test asserted `/run/monitor-power-suspend-wakeup`, which the system-sleep
  pre hook stopped writing in `137a986` (the hook now records the
  `off-until-input` policy instead). The test now asserts the live contract:
  the pre hook writes `/run/monitor-power/policy` and the post hook triggers
  `monitor-power-resume.service`.

### Added

- **charon: tether (iPhone bridge) packaged and enabled** — new `pkgs/tether`
  (CMake build of github:zackb/tether v0.2.18, FetchContent pinned to nixpkgs
  nlohmann_json/gtest), `modules/system/tether.nix` (firewall port 5134 for the
  mTLS endpoint, `tether-btclass@hci0` Class-of-Device fix so bluetoothd's CoD
  reset doesn't break MAP/PBAP) and `modules/home/tether.nix` (user daemon on
  `graphical-session.target`, GTK app, native-messaging host wired into
  firefox/thunderbird/chromium for the OTP extensions). Charon's mDNS moved
  from systemd-resolved back to avahi (tether's Bonjour discovery uses
  avahi-client; resolved now runs with `MulticastDNS = false`). Adversarial
  review fixes: `wrapGAppsHook3` + `gsettings-desktop-schemas` for GTK
  pixbuf/icon-theme loading, `BindsTo` + prepended PATH (not clobbered) on the
  user daemon, `optionalAttrs` guard so `bluetoothAdapter = null` doesn't crash
  eval, and a post-resume sleep hook that re-applies the Class-of-Device fix.

### Fixed

- **makemake: every-boot failure of units gated on `network-online.target`** —
  clan-core's networking module sets `systemd.network.wait-online.enable =
  false`, which masks `systemd-networkd-wait-online` and lets
  `network-online.target` fire ~8s before enp1s0 acquired its DHCP lease.
  Garage provisioners, restic garage bootstraps, the attic bootstrap, nginx
  and atuin failed on every boot. Fixed by re-enabling wait-online pinned to
  the primary NIC (`--interface=enp1s0 --operational-state=degraded`).
- **makemake: `systemd-modules-load` failure on every boot** — dropped the
  nonexistent `iommu` entry from `boot.kernelModules`; the IOMMU is already
  enabled via the `intel_iommu=on` kernel param.
- **storage-alerts: mdadm `PROGRAM` notifier failed with `cat: command not
  found`** — `mdmonitor.service` carries no PATH on NixOS, so the notifier's
  bare `cat` never resolved; use the absolute coreutils path.
- **charon: pi's `agent_browser` tool fails with "Managed-session policy
  coordination is unavailable or busy"** — pi-agent-browser-native probes the
  managed-session lock owner's process start time via `ps` at the hardcoded
  paths `/bin/ps` then `/usr/bin/ps`; NixOS has neither directory. Provision
  `/bin/ps` → procps via an activation script so the deterministic lock path
  works regardless of PATH.

### Added

- **charon: vllm-manager model refresh** — image `intel/vllm:0.11.1-xpu` →
  `0.21.0-xpu` (first XPU line supporting Qwen3.5/Gemma 4 architectures).
  Replaced DeepSeek-R1/Olmo model set with a Qwen3.8-distill lineup
  (Qwen3.5 arch, all fit the 12GB Arc B580 alongside the desktop):
  `tiny` (Qwen3.8-2B-Distill bf16, 4.2 GiB), `small` (Qwen3.8-4B-Distill
  bf16, 8.6 GiB), `medium` (Qwen3.8-9B-Distill W4A16 AWQ, 8.0 GiB).
  Per-model `--gpu-memory-utilization`
  leaves headroom for transient whisper dictation. Real Qwen3.8-27B and
  -Flash-Next need ≥16.8 / ≥167 GiB — out of reach on this hardware.
  Container no longer overrides the image entrypoint (0.21.0 needs
  oneAPI `setvars.sh` sourced for `LD_LIBRARY_PATH`/libccl) and the
  deprecated `--disable-log-requests` flag became `--no-enable-log-requests`.
  Verified end-to-end on charon: API up, chat completion returned.- **io: first backup job** — `backups.home-assistant` (daily restic → B2 of
  `/data/.state/home-assistant`, bucket `restic-io-home-assistant`, lifecycle
  30 d). Requires the `b2` tag in `secrets.discover.includeTags` so the
  shared b2-service credentials are discovered; restic password pre-seeded
  via `clan vars set` (generator prompts are non-interactive otherwise).
  First snapshot verified 2026-08-25.

### Added

- `agent verify eval` validation tier (`.agent/project.json`): evaluates all five machine
toplevels without building — catches option/assertion/config errors in the fast loop that
`fast` (flake metadata only) misses.
- Heartbeat TLS support (`modules/system/heartbeat.nix`): receiver options
`my.heartbeat.receiver.tls.{enable,certFile,keyFile}` terminate TLS directly on the
receiver socket; push option `my.heartbeat.push.caCertFile` pins a private CA for curl
(the endpoint is a raw WAN IP, so there is no ACME name to validate against).
- New shared secret generator `vars/generators/heartbeat-tls.nix` (tag `heartbeat`, so io
and sedna pick it up via existing discovery): CA + server cert with SAN IP 130.61.55.4.
First deploy of io and sedna must regenerate/redeploy vars to materialize the PKI.
- **sedna: backup MX** (`modules/system/backup-mx.nix`): queue-only Postfix that accepts
  mail for `stark.pub` (`relay_domains`) and relays through `mail.stark.pub:25`
  (`relayhost`). `mydestination = ""` ensures no local delivery — the only queue
  action is forwarding. Firewall port 25 auto-opened. Enabled on sedna via
  `my.backupMx.enable = true` (default primary `mail.stark.pub:25`). DNS: add
  `MX 20 mx2.stark.pub.` → `A mx2.stark.pub 130.61.55.4` in Cloudflare manually
  (no MX management in repo). Gatus endpoint `tcp://mx2.stark.pub:25` added to
  sedna's monitoring. VM test suite (`tests/backup-mx.nix`) covers: delivery while
  primary is up, queuing on backup while primary is down + automated flush on
  recovery, no-open-relay rejection of foreign domains, and no local delivery
  (mydestination empty). Registered as `backup-mx-checks` bundle on
  `check-profile-sedna`.

### Changed

- **io→sedna heartbeat encrypted**: push URL is now `https://130.61.55.4:18080/heartbeat`
with `--cacert` pinning; previously the bearer token transited plaintext over the public
internet (review 2026-08-25). Bearer-token auth unchanged; firewall rule unchanged.
- Clan SSH agent forwarding (`clan.core.networking.forwardAgent`) restricted to charon;
was fleet-wide, which let a compromised server reuse the interactive agent over SSH.
- `nix.settings.trusted-users` now grants the main user only where `my.mainUser.enable =
true`; on servers it collapses to `["root"]` (mkForce'd over clan-core's recommended
`["root"]` default, which list-concatenated into duplicates before).
- electron-39.8.10 insecure-package allowance scoped from fleet-wide to the two
workstations that evaluate bitwarden-desktop (charon, ariel); servers never see it.

- Frigate event retention raised to 30 days (top-level `retain.events.days`,
  default was 10); continuous recording stays off. Deployed to io 2026-08-25;
  note: the podman-frigate unit does not restart on config-only switches —
  `frigate-config-sync.service` + `podman-frigate.service` must be restarted
  manually for config changes to reach the container.

### Fixed

- **Heartbeat receiver wedges on a silent TLS client** (`modules/system/heartbeat.nix`):
  the receiver wrapped its *listening* socket (`ctx.wrap_socket(httpd.socket, ...)`),
  so `SSLSocket.accept()` ran the TLS handshake synchronously in the main accept loop.
  A scanner that connects and sends nothing (seen 2026-08-26, 193.176.31.151) stalled
  the single thread in `read()`; the SYN backlog filled (Recv-Q 6 > backlog 5) and every
  inbound connection to 18080 timed out from everywhere — indistinguishable from a
  firewall DROP, which tripped the deadman alert and failover while io was healthy. The
  receiver now wraps each *accepted* socket with `do_handshake_on_connect=False`, moving
  the handshake into a worker thread with a 10 s timeout, and `request_queue_size` is
  raised to 128. Deployed to sedna 2026-08-26; verified a silent connection no longer
  blocks the accept loop (14 ms second connect while a handshake stall was held).

- **air-exhaust fan invisible in Home Assistant** (`modules/system/mosquitto.nix`):
  the mosquitto ACL scoped both clients to `air-exhaust/#` only, so the
  firmware's retained HA discovery configs
  (`homeassistant/sensor/exhaust_c6_{duty,rpm,room,mode}/config`) were
  silently dropped on the write side and the `hass` integration could not
  subscribe to `homeassistant/#` on the read side — the device never appeared
  in HA even though the `air-exhaust/fan/status` and `room_temp` feeds worked.
  The firmware client now also gets `write homeassistant/sensor/#` and the
  hass client `read homeassistant/#`; both stay scoped otherwise. The
  acl-file plugin enforces MQTT wildcard-as-whole-level rules, so a
  prefix-glued `exhaust_c6_#` grant would be rejected at startup; the
  firmware's write grant is `homeassistant/sensor/#`, which matches
  `.../exhaust_c6_{duty,rpm,room,mode}/config`. No
  firmware change needed — the firmware re-publishes its retained discovery
  configs on every MQTT session start, and the deploy's mosquitto restart
  drops its session so it reconnects and republishes within seconds.

### Added

- **rasdaemon on charon** (`machines/charon/configuration.nix`): `hardware.rasdaemon.enable` decodes and persists machine-check exceptions (MCEs) to `/var/lib/rasdaemon/ras-mc_event.db` (query with `ras-mc-ctl`). Motivation: the Aug 19 hard reset was associated with uncorrectable EX-watchdog MCEs (Bank 5/22) that the kernel only prints once at the next boot — rasdaemon keeps a running record and also surfaces correctable errors.

- **Mosquitto MQTT broker on io** (`modules/system/mosquitto.nix`, `machines/io/configuration.nix`): LAN-only listener on `10.0.0.1:1883` (`allow_anonymous false`) with two clients — `air-exhaust` (the exhaust-c6 ESP32 fan controller) and `hass` (Home Assistant's `mqtt:` integration) — each scoped by ACL to `air-exhaust/#`. The clan-vars shared secret `air-exhaust-mqtt` generates random per-client passwords (`mosquitto_passwd` hashes for systemd-credential delivery, plus cleartext `*.env` files for the firmware and HA); generated 2026-08-18. Port 1883 opened on the trusted segment (`routerAllowedTcpPorts`).

### Fixed

- **HA MQTT wiring lost on configuration.yaml regeneration** (`modules/system/home-assistant.nix`): the old `homeassistant-reverse-proxy-config` one-shot regenerated `configuration.yaml`, dropping the hand-maintained MQTT config on 2026-08-18 (air-exhaust room-temp publish broke). The first fix appended a declarative `mqtt:` block — but on HA 2026.8+ a YAML `mqtt:` block with `broker/port/username/password` is **invalid config** (mqtt is config-entry based now), so mqtt setup failed, which cascaded into frigate (depends on mqtt) and the automation's `mqtt.publish` action. Resolution: the one-shot service is **removed entirely** — on 2026.8 the HTTP reverse-proxy trust lives in `.storage/http` (Settings > System > Network) and the MQTT broker wiring is a config entry in `.storage/core.config_entries`; neither belongs in `configuration.yaml` (the http YAML block is also ignored after migration and stops working in 2027.2). The stale `mqtt:`/`http:` blocks were deleted from the live config. Verified post-fix: zero setup errors, `hass` reconnects to mosquitto from the config entry, frigate loads again, retained `air-exhaust/room_temp`/`room_humidity` publishes flow.

- **`Mod+Ctrl+L` no longer suspends on charon** (`modules/system/ddcutil`): the keybind (added in `13e6d09`) spawns `system-suspend` in the user session, but `137a986` gave the script root-only writes to `/run/monitor-power/policy` under `set -euo pipefail` — so the session spawn aborted with EACCES before `systemctl suspend`. The policy write is now root-gated (`id -u`); the ddcutil systemd-sleep pre hook still writes the same `off-until-input` policy at actual sleep, and `monitor-power off` still runs before suspend. Charon-only as intended (the bind only resolves where ddcutil monitor control is enabled); `auto-suspend` on charon is unaffected (it runs the same script as root).

- **Accounted stack down since Aug 11 reboot** (`modules/system/accounted.nix`): `accounted-stack` started before systemd-networkd had the DHCP lease on enp1s0, so docker could not bind the host port `10.0.0.10:3050` (`cannot assign requested address`) and the app container was created without any network endpoint. Compose then treated the broken container as up-to-date forever (config hash unchanged), so every restart reused it: the app could not reach Supabase, `/api/health` failed, and `up -d` aborted waiting for the `service_healthy` cron dependency. The unit now waits for the bind address (`ip addr` loop, 180s cap) before running compose, and `up -d` passes `--force-recreate` so a stale/networkless container is replaced instead of reused. Verified: recreated the container on makemake, app healthy, `https://accounting.lan.stark.pub/api/health` returns 200 via the router, cron running.

- **charon monitor turning on after WoL** (`modules/system/ddcutil`): kernel sysfs/IRQ wake-source is unusable here (`igb` wakeup counters stay 0 on S3; `/sys/power/pm_wakeup_irq` empty), and waiting for io's keep-awake SSH delayed every local wake. Resume now forces DDC off (defeats HDMI auto-on); `monitor-power-input` turns the panel on only from physical USB HID / power-button evdev (not Sunshine uinput). The wake-proxy lease now overrides stale resume-time input and runs after the resume force-off, preventing concurrent DDC writes from leaving the panel on; physical input during or after that force-off still turns it on. Covered by `monitor-resume-classification`.
- **pi-web unusable behind `wake.stark.pub`** (`modules/system/wake-proxy.nix`): the public vhost inherited the shared 10r/m `limit_req` zone. The SPA fires dozens of API/SSE requests on load, so nginx 503s mid-page and the UI looks broken while the frontend still loads. Exempt like the other interactive SPAs (`rateLimit = null`); fail2ban still covers path scanners.
- **io completely failing to boot after reboot** (`modules/system/router/network.nix`): the `10-igc-no-eee` systemd.link (added Jul 31 to disable EEE on the Intel I225/I226 NICs) matched `Driver=igc` without `Name=`/`NamePolicy=`, shadowing systemd's `99-default.link` — udev stopped renaming, interfaces came up as `eth0`–`eth3`, and every enp-keyed networkd/nftables rule silently failed to match (no WAN DHCP, no bridge ports). The EEE override itself never worked before (the `igc.eee_enable=0` module param is dead — igc has no such param), and a year of EEE-on operation was stable, so the link file is removed entirely; naming (and EEE default) now follow systemd defaults again. Additionally `systemd.network.wait-online` was scoped to wait only for the primary LAN segment (`--interface=vlan1 --operational-state=degraded`, 30s timeout) instead of every routed VLAN plus WAN `RequiredForOnline=routable`, which hung boot indefinitely whenever the ISP link was down. (`machines/sedna/configuration.nix`): `heartbeatTimeoutMinutes` raised 5 → 10 (io's `*:0/5` push with the 2m randomized delay let healthy gaps reach ~7 min, exceeding the old timeout; 866 false "heartbeat lost" events/week, real DNS PATCHes flipping public domains to the maintenance page). io's `heartbeat.push.randomizedDelaySec` lowered 2m → 30s to shrink jitter.
- **ddclient never updating on io** (`modules/system/router/nginx.nix`): ddclient 4.x daemonizes by default — the oneshot units exited 0 in ~150ms doing nothing and left zombie daemons, so `nous.fyi` stayed pointed at sedna's maintenance page for 2 days after a failover flap. Units now run `--foreground` with a writable per-zone cache (`/var/lib/ddclient` via `StateDirectory`) and no `daemon=` line (4.x treats `daemon=0` as a 60s loop that never exits). Verified: records restored, both zones run clean, timers healthy.
- **`chat.stark.pub` ACME order failing daily on io** (`modules/system/openwebui.nix`): the LAN-only vhost got a per-vhost HTTP-01 order against no public A record (`no valid A records found`, system `degraded`). LAN-only openwebui vhosts now set `noAcme = true`; the failing unit is gone after rebuild.
- **charon `systemd-journal-upload` crash loop** (`machines/charon/configuration.nix`): a giant `COREDUMP_STACK_TRACE` from crashing QtWebEngine/garage processes (10 MB+ entries, rejected by nginx's body limit) wedged the uploader since Aug 3. `systemd.coredump.settings.Coredump.ProcessSizeMax = "512M"` caps future in-journal backtraces; uploads verified flowing to io's collector again (4313 charon entries received).
- **charon auto-suspend ignoring activity / never firing** (`modules/system/auto-suspend.nix`): the decision keyed off logind's session `IdleHint`, which swayidle is the only writer of — Wayland idle-inhibit (Electron apps, video players) kept it stuck at `no` (auto-suspend never fired), and the `treatStaleIdleHintAsIdle` heuristic that followed misread a user typing for 10+ minutes as idle. Auto-suspend now tracks real input directly: `auto-suspend-input-watch` records the last evdev event (physical input plus uinput virtual devices such as Sunshine's) to `/run/auto-suspend/last-input`, and the check treats ≥ `userIdleSeconds` without input as idle. `treatStaleIdleHintAsIdle` removed; block-mode sleep inhibitors and the load/TCP gates are unchanged. Covered by new VM tests driving a real uinput device (`auto-suspend-input-keeps-active`, `auto-suspend-input-idle-suspends`).
- **agentcad MCP runs aborting on charon** (`machines/charon/configuration.nix`): OCP's offscreen GL renderer cannot create a GLX context on this host and aborts the whole process with an X error on a live display — killing the auto-diff PNG phase of every `agentcad run` that has a previous version (agentcad 0.4.0 has no `--no-diff`). The agentcad MCP server entry now sets `env.DISPLAY = "invalid-display"`, which fails the GL phase gracefully (connection error → warning → run completes). Verified: charon toplevel builds; the generated `~/.pi/agent/mcp.json` carries the env.
- **journal-upload crash loop on charon/ariel/makemake** (`modules/system/router/security.nix`): systemd-journal-upload aborts with `Buffer space is too small to write entry` / EIO (exit 1, restart loop) when libcurl hands its read callback a small trailing buffer while starting a new entry under HTTP/2 — systemd#39166, still open upstream. nginx ≥ 1.25.1 enables h2 by default on ssl listeners, so the LAN-facing journal-upload endpoint (10.0.0.1:19532) now sets `http2 off;` (server directive), keeping the upload on HTTP/1.1.
- **pg_dump artifacts inside restic snapshots** (`machines/makemake/configuration.nix`): `nous_prod.dump` / `paperless.dump` are written into the restic data dirs, embedding a redundant copy in every snapshot. Both jobs now exclude the dump path.
- **libvirt pool not autostarting** (`modules/system/libvirt.nix`): NixVirt 0.6.0 has no pool autostart support; a oneshot `libvirt-pool-autostart` service (after libvirtd) runs `virsh pool-autostart` for declared pools.

### Changed

- **Home Assistant container pinned to 2026.8.2** (`modules/system/home-assistant.nix`): the image was `:stable` — with podman's default `missing` pull policy it was never re-pulled, so the container silently ran a 14-month-old image (2025.6.1 / Python 3.13) while HACS components moved on, breaking the frigate integration (`hass-web-proxy-lib==0.0.8` needs Python ≥ 3.14.2). Upgraded live on 2026-08-18 with rollback tag `2025.6.1-rollback` and a full config backup; the tag is now pinned and must be bumped deliberately together with the frigate (≥ 5.15.4) and plejd (≥ 0.20.x) component versions. Also during the upgrade: plejd component 0.13.1 → 0.20.7 (py3.14 compatibility, major backend rewrite), and the invalid `go2rtc: streams: {}` block that broke `default_config` was removed from the runtime `configuration.yaml`. Verified post-upgrade: HA 2026.8.2/py3.14, frigate integration loads (32 entities, `camera.reolink_p330` present), plejd lights registered, MQTT retained publish (`air-exhaust/room_temp` 27.37 / `room_humidity` 37.3) flowing, ZHA sensors reporting.

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

### Fixed

- **sedna-failover: `skipDnsRevert` now defaults to `false`** — the old default delegated revert to ddclient on io, whose cache never reconciles out-of-band failover PATCHes (2026-09-02: traffic stuck at sedna 10h). Sedna now self-heals via the stored `dns-state.json`; the incident rationale moved into the option description and sedna's override was removed.
- **sedna-failover: revert survives partial Cloudflare PATCH failures** — the revert script prunes each converged domain from `dns-state.json` as it goes, keeps failed entries, and exits non-zero (`Revert incomplete`) so the timer retries only what's left and the failure surfaces. New `sedna-failover-revert-partial` VM test (mock 422s one record): loud failure, pruned state, safe retry.
- **backups: restore units are manual-start and restore in-place; timers survive restore mode** — `restic-restore-*` lost its `wantedBy` (deploying can no longer trigger a restore; VM test asserts `inactive` after a fresh boot with restore mode on), `restore --target /` writes files back to original locations instead of nesting them under `path`, scheduled backups + failure alerts stay wired while restoring, and eval warns naming any job in restore mode. README restore flow rewritten to match.
- **router monitoring: Grafana `secret_key` via `$__file` provider backed by Clan vars** — the hardcoded key is out of `/nix/store` (new `vars/generators/grafana.nix`, read access for the `grafana` service user on io). The `router-wireguard-admin` VM test provisions a dummy key for the stub. Grafana is still disabled fleet-wide, so this is latent hygiene, verified by eval + full `router-checks`.
- **garage: S3/RPC bound to LAN IPs with scoped firewall; world-readable-secrets override removed** — new `bindAddress` option (default `127.0.0.1`; io `10.0.0.1`, makemake `10.0.0.10`), `allowedTCPPorts` replaced with LAN-only `mkRestrictedPortRules`, same-host consumers moved off localhost. `GARAGE_ALLOW_WORLD_READABLE_SECRETS` + the setfacl entry are gone: garage runs as root and reads the `0400` file directly — the ACL's mask bits were what tripped garage's permission check, so the override was compensating for the ACL itself (`87932fa` had no rationale recorded). Correction: io was never WAN-exposed (firewall off, nftables-scoped); makemake was.
- **checks wiring: `accounted-checks` runs under `nix flake check`; charon gains desktop profiles** — the accounted bundle was defined but never merged into `checks` (CI green, test never ran). New `check-profile-tether/auto-suspend/monitor` mappings tag charon; `check-profile-mailserver` was verified present (review claim was stale); README profile table now matches the resolver.

### Fixed

- **backup-mx: 30d queue lifetime plus queue depth/age watch** — `maximal_queue_lifetime`/`bounce_queue_lifetime` 5d → 30d so queued mail outlasts extended outages. New hourly `backup-mx-queue-watch` (depth > 100 or oldest age > 72h) mails once-until-recovered through smtp2go reusing the gatus env secret; without an env file the breach is still loud via the failed unit. New `backup-mx-queue-watch` VM test (lifetime via `postconf`, empty-queue exit 0, breach fails loudly, retry still loud).
- **`machine-update-plan` fails closed on tagless machines** — zero `check-profile-*` tags used to silently resolve to treefmt-only deploys; now a hard error naming the machine and the fix. Verified both directions (crafted zero-tag env exits 1, explicit `check-profile-fast` still resolves).
- **storage-alerts: no more `/boot` pages, bounded sweeps** — capacity `excludeMounts` defaults to `["/boot" "/efi"]`; per-target `df -l` wrapped in `timeout 10` with an explicit "unreadable" branch (previously a bogus "recovered"); every notifier call isolated with `|| true` so one dead target or unreachable ntfy can't abort the sweep; unit capped with `TimeoutStartSec = 3min`. Sweep logic proven with a harness (hanging-`df` shim + always-failing notifier → exit 0, unknown branch taken, sweep completes).
- **heartbeat: push failures alert locally; push/Gatus tokens split (opt-in)** — `heartbeat-push` gained `onFailure` to a once-until-recovered ntfy alert (recovery announced, flag cleared on next success); new `push.failureNtfy` options, wired on io with a dedicated `heartbeat` topic + `heartbeat-token` (ntfy generator extended, old provisions upgrade without rotation). New `receiver.gatusApiTokenEnvVar`: null keeps legacy single-token behavior; setting `HEARTBEAT_GATUS_TOKEN` (auto-appended by the heartbeat generator on regeneration) separates the WAN bearer from the Gatus API token with fallback + journal warning instead of crash-looping. New `heartbeat-push-receive-alert` VM test (split-token end to end, 403/204 separation, alert-once, no re-alert, recovery) wired as `heartbeat-checks`.
