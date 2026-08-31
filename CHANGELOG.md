# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

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
