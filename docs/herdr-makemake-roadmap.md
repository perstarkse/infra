# Roadmap: herdr on makemake, owned by `agent`

Moving the *primary* herdr web frontend to `makemake` so lightweight work never
has to wake `charon`, with the agent toolchain and the Hermes gateway both
running natively as the fleet's `agent` account.

Everything marked **verified** was checked against the running system or the
named file:line. Corrections from an independent review are folded in and
listed under "Review corrections".

## Motivation

`charon` is a 5950X with a discrete GPU that draws real power whenever awake. It
is woken ~5x/day (37 deep suspends in 7 days of journal). Moving lightweight
agent work to always-on `makemake` removes those wake cycles.

**The energy saving has not been quantified.** Wall power needs a smart plug or
BMC; neither machine exposes one. The rationale is qualitative.

## Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | herdr server and agent toolchain run as **`agent`**, not `hermes` | The agent *is* `agent`; `hermes` is only the gateway. Panes are spawned by the herdr server, so this also fixes the identity any LLM runs as. |
| D2 | Give `agent` a real Home Manager profile | `agent-tooling` exposes `pi-agent`/`antigravity` as **homeModules only** (`nixosModules: []`, verified). Otherwise you write NixOS-scope equivalents for two agents. |
| D3 | Hermes moves container → native | Once panes run as `agent` on the host, the LLM already executes arbitrary code on the host. The container only walls off the gateway, not the work. |
| D4 | Project space is `/home/agent/projects/` | Owner-confirmed. `agent` gets a conventional home at `/home/agent`. |
| D5 | ~~charon's herdr instance is retained~~ — **cut over 2026-10-11**: `herdr.lan.stark.pub` moved to makemake; charon's bridge stays installed but unpublished | Owner decision after makemake evaluated healthy. |
| D6 | Auth is deferred | Out of scope — see Risks. |
| D7 | Fleet SSH key must move from `hermes` to `agent` | Follows from D1+D3. The gateway, running as `agent`, is what needs the key. **This makes what was an optional hygiene item mandatory.** |

### D3 eliminates a container mount

Gateway and herdr both native as `agent` ⇒ the gateway reaches
`/home/agent/.config/herdr/herdr.sock` **directly**: no bind mount, no SSH hop,
no socket ACL, no container identity change.

## Status 2026-10-11 (lockdown)

All phases A–H are landed and verified on the live machines: `agent` has a
writable home + HM profile on makemake and charon, herdr runs as a HM user
unit on both, the gateway is native as `agent`, the mesh is bidirectional,
the toolchain (pi + agy) is installed, and `herdr.lan.stark.pub` serves from
makemake with `herdr-charon.lan.stark.pub` alongside. The system-scope
`modules/system/herdr.nix` is deleted; `flake/lib/herdr-sockets.nix` is
deleted with it (its only consumer was the `shareWith` ACL path).
Collaboration-space decision (agy-reviewed): `/home/p/repos` stays a symlink
to `/mnt/sdb/repos` (rename = retarget the symlink, keep a compat link —
moving the real dir orphans pi sessions, herdr `session.json` cwds and git
worktrees); permissions stay ACL-per-path, no shared group. The rename
itself is NOT done — design only.

## Current verified state (pre-execution snapshot; see Status above)

| Fact | Evidence |
|---|---|
| `charon` herdr is an HM **user** service as `p` | `systemctl --user show herdr` |
| `makemake` herdr is a **system** service as `hermes` | `modules/system/herdr.nix` |
| makemake panes inherit a near-useless `PATH` — no `/usr/bin`, so no `git`, no `ssh` | only coreutils/findutils/grep/sed/systemd store paths. **Defect introduced by this work; Phase C fixes it.** (`git` *is* on the system profile — the defect is the pane PATH, not a missing package.) |
| `agent` on makemake: uid 1001, home `/var/empty/agent` | `getent passwd agent` |
| `/var/empty` is root-owned 0555, deliberately | `agent-ssh-access.nix:75` |
| **The fleet SSH private key is exposed to `hermes`, not `agent`** | `hermes.nix:421` `user = "hermes"`; the key ships to `/var/lib/hermes/home/.ssh/id_ed25519`. `agent` only receives the *public* half at `/etc/ssh/authorized_keys.d/agent`. |
| Mesh is bidirectional, verified | `herdr machine list` shows the peer on each side |
| `wake-charon` works on makemake | magic packet + TCP-poll of `10.0.0.15:22` |
| pi's credential tags absent from makemake | `includeTags` lacks `openai`/`openrouter`/`context7` |
| Container: `ubuntu:24.04`, `User=` empty, not privileged, no userns-remap | main process runs as `hermes` |
| `docker exec` **without `-u` runs as uid 0** | `docker exec hermes-agent id` → `uid=0(root)` |

## Target state

```
makemake  ── agent (native, HM profile)
            ├── Home Manager profile            (root-declared, reproducible)
            ├── herdr user service              ~/.config/herdr/herdr.sock
            ├── pi + agy via agent-tooling     homeModules
            └── Hermes gateway (native)         direct socket access

charon    ── p (unchanged): herdr + herdr-web-ui on herdr.lan.stark.pub
```

## Security model

1. **Anything that must be trustworthy goes in Home Manager.** Root-owned,
   reproducible, self-healing — drift is corrected by the next deploy rather
   than by trusting the agent's discipline.
2. **Anything the agent must mutate stays out of Home Manager.** caches,
   `node_modules`, build output.
3. **Never let the agent's writable space overlap a trust boundary.**

### Prerequisites this exposes

**Phase A is a security prerequisite.** `agent-ssh-access.nix:70-79` states that
sshd reads `~/.ssh/authorized_keys` *in addition to* `/etc/ssh/authorized_keys.d/%u`,
that `services.openssh.authorizedKeysInHomedir` has no per-user override, and
that the non-writable home is therefore the *only* thing stopping the agent
authorizing itself. A writable home removes that. Closed per-user (not globally)
by extending the existing `Match User agent` block:

```nix
services.openssh.extraConfig = lib.mkAfter ''
  Match User ${config.my.agent-ssh-access.user}
      AuthorizedKeysFile /etc/ssh/authorized_keys.d/%u
'';
```

Verified `services.openssh.authorizedKeysInHomedir = true` on makemake.

**Accepted exposure:** charon's fleet key sits at `/home/p/.ssh/herdr-mesh_id_ed25519`,
so every coding agent running as `p` can become `agent` fleet-wide. Owner
decision; recorded so it is not forgotten.

## Module-surface constraints (from review — these decide how phases land)

Every item below was verified against the named file:line. Several roadmap steps
that *look* like a one-line machine-config change are in fact **module changes**,
because the option is hardcoded rather than defaulted.

| Constraint | Where |
|---|---|
| `services.hermes-agent.container.enable` is **derived** from `my.hermes.enable` — not a knob you can set false | `hermes.nix:292-294` `container = { inherit (cfg) enable; … }` |
| `users.users.agent.createHome = false` is hardcoded | `agent-ssh-access.nix:139` |
| `my.agent-ssh-access.home` already *is* `users.users.agent.home` | `agent-ssh-access.nix:133-137` |
| `my.herdr.package` has **no default** in the HM module | `modules/home/herdr.nix:143-147` |
| `my.herdr.sshConfig` exists **only** in the system module | `modules/home/herdr.nix` has 0 occurrences |
| the HM herdr module cannot set `environment.systemPackages` | comment at `modules/home/herdr.nix:217-220` |
| hermes secret ACLs hardcode the literal `"hermes"` | `hermes.nix:384` `readers = ["hermes" "signal-cli"]`, `:389`, `:421` |
| `requireGenerators` takes **generator names**, not tags | `makemake/configuration.nix:192` vs charon's use of `"context7"` |
| `api-key-openai`/`openrouter` read grants are gated on `mainUser.enable` and name `mainUser.name` | `shared.nix:168-175`, skipped entirely when `mainUser.enable = false` |
| `herdr-web-ui`'s endpoint/firewall options live in the **NixOS** module; the HM module has only `bindHost`/`pluginRepo`/`enable` | `modules/system/herdr-web-ui.nix`, `modules/home/herdr-web-ui.nix:76-88` |
| `makemake` does not import `home-module` at all | `machines/makemake/configuration.nix:8-70` |
| `shareWith = ["agent"]` is a **no-op** once herdr runs as `agent` (it ACLs agent's own socket) | `flake/lib/herdr-sockets.nix:42-45` |
| `bindHost` already defaults to `osConfig.my.listenNetworkAddress` | `modules/home/herdr-web-ui.nix:82` |

## Phases

### A — `agent` gets a writable home

- Extend `agent-ssh-access.nix`: add a `createHome` option (default `false`) or
  make the existing `createHome = false` a `lib.mkDefault`, so machines can opt in.
- Set `my.agent-ssh-access.home = "/home/agent"` — that is what actually drives
  `users.users.agent.home`; do not also set `users.users.agent.home`.
- Create `/home/agent/projects/` owned by `agent`.
- **Same phase:** add the `AuthorizedKeysFile` `Match User agent` block.
- Decide the fate of `/var/lib/agent-work` (the module's scratch option).

*Exit:* `agent` can write its home; a self-written `~/.ssh/authorized_keys` is
**ignored** (test by writing one and confirming `ssh agent@…` still uses the
restricted key).

### B — Home Manager for `agent`

- Add `home-module` to makemake's NixOS `imports` (absent today). Without it the
  `home-manager` options do not exist at all.
- `home-manager.users.agent` with imports from the correct namespaces:
  `ctx.flake.homeModules.{options,sops,ssh}` and, in Phase F,
  `ctx.inputs.agentTooling.homeModules.*`. Bare `options`/`sops`/`ssh` will not
  resolve in that scope.
- `my.mainUser` stays disabled.

*Exit:* `home-manager-agent.service` succeeds; `agent`'s profile is populated.

### C — herdr becomes a Home Manager user service for `agent`

Retire `systemd.services.herdr` from `modules/system/herdr.nix` (delete the module
if nothing else uses it). This phase has four mandatory side-effects that are
easy to miss, each verified above:

1. `my.herdr.package` has no default in the HM module — set it explicitly from
   the locked input, as charon does.
2. Add herdr to `environment.systemPackages` in the machine config — the HM
   module cannot, and without it non-login `ssh agent@makemake 'herdr …'` fails
   with `herdr: command not found`, silently breaking the mesh.
3. Migrate the outbound mesh config: `my.herdr.sshConfig` does not exist in the
   HM module. Use `home.file.".ssh/conf.d/herdr-mesh"` (the charon pattern).
   Note the current `IdentityFile` is `hermes`-owned `0400` and unreadable by
   `agent`, so `agent` needs its own identity key regardless (see Phase E).
4. Update the existing `Match User agent` `SetEnv HERDR_SOCKET_PATH`, which
   currently interpolates `config.my.herdr.stateDir` and would either fail
   evaluation or point at the dead `/var/lib/hermes/...` path.

Drop `shareWith = ["agent"]` — it would ACL agent's own socket.

*Exit:* panes on makemake have a working `PATH` (`git`, `ssh` resolve), **and**
`ssh agent@charon 'herdr agent list'` still works.

### D — Hermes container → native

Three module changes, not machine-config flips:

1. `services.hermes-agent.container.enable` is derived from `my.hermes.enable`.
   Introduce a real option (e.g. `my.hermes.containerMode`, defaulting to the
   current behaviour) rather than setting the derived value directly.
2. Change the hardcoded `"hermes"` literals in `hermes.nix` (lines 384, 389, 421)
   to the configured user, keeping `"signal-cli"` in the ACL readers.
3. **`linger = true`** must be set explicitly on `users.users.agent`, or cron
   degrades to unscoped workers.

The `container-bin` symlinks (`/opt/himalaya`, `/opt/wake-charon`) stop being the
delivery mechanism; those tools must be on `agent`'s PATH instead.
`docker.enable` stays — makemake uses Docker for other things.

*Exit:* gateway native as `agent`; `hermes-inspect status` healthy; Signal
round-trip and mail both work; a scheduled cron job runs **scoped**.

### E — Fleet identity for `agent` (now mandatory, per D7)

The gateway runs as `agent` and needs the fleet SSH key, which today is exposed
only to `hermes`. Move `my.secrets.exposeUserSecrets` from `hermes` to `agent`
(`hermes.nix:418-426`), and resolve the outbound-mesh `IdentityFile` from Phase
C.3 against the new location.

*Exit:* `agent` can `ssh agent@charon` without a password; the mesh works
outbound from makemake.

### F — Agent toolchain (the expensive phase)

- Import `agentTooling.homeModules.{pi-agent, antigravity, shared-skills}`.
- **Secrets — two distinct things, easy to conflate:**
  - `includeTags`: add the tags that select the generators.
  - `requireGenerators`: add **generator names**, not tags — `"api-key-openai"`,
    `"api-key-openrouter"`, `"context7"`.
  - **Read access:** the existing grants in `shared.nix` are gated on
    `mainUser.enable` and name `mainUser.name`; on makemake they are skipped
    entirely, and secrets land `0400 root:root`. Add explicit
    `my.secrets.allowReadAccess` entries with `readers = [ "agent" ]`.
- **Runtime:** establish what pi needs (node/bun — `hermes` has neither today).
- `herdr integration install pi antigravity-cli` comes free with the HM herdr
  module; note the ordering constraint (after pi-agent lays down `~/.pi/agent`).

*Exit:* a pane on makemake runs authenticated `pi` and `agy`.

### G — herdr-web-ui under `agent`

Needs **both** halves, not one:

- NixOS `herdr-web-ui` module imported on makemake (absent today) for the
  endpoint, port and firewall (`allowedFirewallSources = [ "10.0.0.1" ]`).
- HM `herdr-web-ui` under `home-manager.users.agent` for the plugin install,
  pinned bun and `HOST`. Do **not** set `bindHost` — it already defaults to
  `listenNetworkAddress`.
- **Second domain** (e.g. `herdr-mk.lan.stark.pub`) so charon's keeps serving (D5).
  io's `endpoints.imports.machines` already includes `makemake`.

*Exit:* the new vhost returns HTTP 200 from io; charon's is untouched.

### H — Driving charon from makemake

**Depends on C and E** (needs panes on makemake and an outbound identity).

```fish
wake-charon wake                          # blocks until charon's sshd answers
ssh agent@10.0.0.15 'herdr agent list'    # mesh
```

Auto-suspend untouched: charon's `sleepInhibit` holds only while an agent reports
`working` (1800s ceiling).

**Gap:** a direct WOL does not engage wakeproxy's keep-awake lease — that is only
taken via `wake.stark.pub`. Long runs could hit the ceiling and suspend mid-work.
- *cheap:* rely on `sleepInhibit`, refresh by touching the agent.
- *better:* extend `wake-charon` to `ssh wakeproxy-keep-awake@charon
  wakeproxy-keep-awake-target <seconds>`. The script is already on charon's system
  PATH, but `vars/generators/wake-proxy-keep-awake-ssh.nix:10-17` writes the key
  `0400 root:root` when `services.wakeproxy.enable = false` (makemake's case), so
  an explicit `allowReadAccess`/`exposeUserSecrets` grant is required.

## Sequencing

| Phase | Depends on | Unlocks | Size |
|---|---|---|---|
| A | — | everything (security gate) | small |
| B | A | C, F | small |
| C | B | fixes the pane-PATH defect; keeps mesh alive | small |
| D | A | removes the container-mount problem | medium |
| E | A, C | outbound mesh identity | small |
| F | B, C, E | usable panes | **large** |
| G | B, C | second frontend | small |
| H | C, E | driving charon | small |

A and C are the best value per unit of effort: A is a security gate, C fixes a
live defect and protects the mesh. Do not start F until A–C are proven.

## Review corrections

An independent review (agy) proposed 17 findings; **16 were verified correct and
folded in**, all listed in "Module-surface constraints" and the phase bodies.

**Rejected:** the claim that `git` is absent from makemake's system packages.
False — `/run/current-system/sw/bin/git → git-minimal-2.54.0` is present. The pane
`PATH` defect is real, but it is not caused by a missing package.

The high acceptance rate reflects how the review was run: specific files named,
factual errors ranked as the top priority, prose and feature suggestions excluded.

## Risks

- **Auth stays off (D6).** This puts a `role: "drive"` frontend on an
  always-on, LAN-reachable server with `HERDR_WEB_TOKEN` unset. Live health
  reports `{"auth":{"required":false,"via":"open","role":"drive"}}`. Build
  everything, but do not make this the daily driver before auth is on.
- **Writable home for `agent`** — Phase A is only safe with the
  `AuthorizedKeysFile` block in the same change.
- **Phase C touches the mesh.** Four separate side-effects; a partial phase
  silently breaks `ssh agent@makemake` from charon.
- **Cron under native Hermes** needs `linger`, degrades silently otherwise.
- **Phase F is undersized in most plans** — credentials, runtime and integration
  ordering are three distinct problems.
- **Energy benefit unmeasured.** See Motivation.

## Explicitly out of scope

- charon's herdr instance and `herdr.lan.stark.pub` (retained, D5)
- Auth for the web frontend (D6)
- Moving project data onto makemake storage
- `docker exec` root hardening (real finding, separate change)