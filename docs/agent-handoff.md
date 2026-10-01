# Handoff: personal agent (Hermes) on makemake

Briefing for the next agent continuing this work. Everything below was verified
against the running system; where something is unverified or in-flight it says so.

## Mission

A personal AI agent on `makemake`, reachable over Signal, running in a container
so it can `apt`/`pip`/`npm` install. It reads fleet state over a non-sudo SSH
identity and is designed to work with the owner's `infra` and `homelab` repos.
Deliberately channels-only: no browser dashboard (see "Open questions").

## Where it runs

| | |
|---|---|
| Host | `makemake` (10.0.0.10), NixOS, Intel N100 / 32 GiB, Docker + podman |
| Agent runtime | Hermes Agent, pinned flake input `github:NousResearch/hermes-agent` at rev `ea114c3e98c3339e13004adfc6098cf28ed7d754`, **container mode**, docker backend |
| signal-cli | `pkgs/signal-cli` (release package, **0.14.8**, JDK 25) — NOT nixpkgs' 0.14.2 |
| Provider | `custom:commandcode` → `https://api.commandcode.ai/provider/v1` |
| Model | `meta/muse-spark-1.3-contributor`, `agent.reasoning_effort: high` |
| Signal | one linked device on the owner's own number; DM-only allowlist |

Units on makemake: `hermes-agent`, `signal-cli`, `install-agent-authorized-key`,
`agent-path-acl`, `agent-workdir`.

Live state (verified): `hermes-agent` active NRestarts=0, `signal-cli` active,
SSE socket held between the `hermes` and `java` processes on :8085, agent
answers prompts through commandcode.

## Access

```bash
clan ssh makemake                 # interactive shell
clan ssh makemake -c /path/to/bin # execs ONE binary — not a shell
clan ssh makemake -c /run/current-system/sw/bin/bash -c 'cmd'   # /bin/bash does not exist
```

**`clan ssh` failed with `Permission denied (publickey)` until `SSH_AUTH_SOCK` was
set.** The key is already in the system agent; the env var was simply unset:
`export SSH_AUTH_SOCK=/run/user/1000/ssh-agent`. If auth fails again, check that
first — it is not a deployment problem.

## Repo layout (conventions you must follow)

- `modules/system/*.nix` are auto-imported by `(inputs.import-tree ../../modules)`.
  A file `foo-bar.nix` must define `config.flake.nixosModules.foo-bar`.
- `vars/generators/*.nix` are Clan vars, deployed to
  `/run/secrets[-for-users]/vars/<name>/<file>`. **Never readable at Nix eval
  time.** `my.secrets.getPath` throws at eval on an unknown name.
- `my.secrets.allowReadAccess` → setfacl readers. `my.secrets.exposeUserSecrets`
  copies a users-scope secret into a user-owned path.
- `config._module.args.mkHardenedServiceConfig` and `mkRestrictedPortRules` are
  fleet helpers. Custom release packages: `pkgs/<name>/default.nix` with a
  `sha256 ?` default, wired via `pkgs.callPackage ../../pkgs/<name> { }` and an
  overridable `package` option (see `modules/system/signal-cli.nix`).
- Gates: `nix fmt` then `agent verify fast|mid|full`. CHANGELOG entry required
  for behaviour changes. `agent guard check`.

## Verified facts about Hermes (read from the pinned source, not docs)

Config lands in `$HERMES_HOME/config.yaml`; `.env` from `environmentFiles`.

1. **`model.default` must be the BARE model id** when a provider is named
   beside it. `split_model_config_default()` (config.py:1769) never splits a
   `provider/model` pair out of the string — `custom:commandcode/meta/muse-…`
   makes it strip only `custom:` and send `commandcode/meta/muse-…` on the wire →
   `HTTP 400 … is not a valid model ID`. Hence `model` + `modelProvider`.
2. **`reasoning_effort` is not a provider key.** `_KNOWN_PROVIDER_KEYS`
   (config_providers.py:114) omits it, so it is silently dropped with an
   "unknown config keys ignored" warning. The main model's effort comes from
   `agent.reasoning_effort`, or per-model `agent.reasoning_overrides`
   (`resolve_reasoning_config`, hermes_constants.py:1109). Valid levels:
   minimal, low, medium, high, xhigh, max, ultra.
3. **Provider-entry keys are snake_case** (`base_url`, `api_mode`, `key_env`).
   camelCase is auto-mapped but warns per key.
4. **Custom-provider credential env var** is derived:
   `HERMES_CUSTOM_` + name uppercased with non-alphanumerics → `_` + `_API_KEY`
   (`custom_endpoint_key_env`, config.py:2747). `key_env` overrides it — which is
   what we use, pointing at the existing `COMMANDCODE_API_KEY`.
5. **`container.enable = true` forbids `backend.mode`** — an enforced assertion
   (nixosModules.nix:410), not prose. Container mode also runs `--network=host`
   and mounts `/nix/store` ro + `${stateDir}` → `/data`; `$HOME` is
   `${stateDir}/home`.
6. **`environmentFiles` is merged only in a system activation script**
   (nixosModules.nix:455), never in the container's preStart. Hence the custom
   `hermes-env-rotation` unit that re-renders `.env` then
   `try-restart || start`s both consumers.
7. **Secret rotation needs no deploy**: `systemd.paths.hermes-env-rotation`
   watches the file; the restarter re-renders `.env` and restarts
   `hermes-agent` and `signal-cli`.
8. Signal adapter reads `SIGNAL_HTTP_URL` + `SIGNAL_ACCOUNT` (required),
   `SIGNAL_ALLOWED_USERS`, `SIGNAL_GROUP_ALLOWED_USERS` (unset = groups off),
   `SIGNAL_REACTIONS`, `SIGNAL_REQUIRE_MENTION` via plain `httpx` URLs — so
   signal-cli's `--socket` is unusable, and its HTTP/TCP interfaces have **no
   authentication at all**.
9. Gateway authorization order: pairing store → per-platform allowlist →
   `GATEWAY_ALLOWED_USERS` → `GATEWAY_ALLOW_ALL_USERS` → **default deny**. With an
   allowlist set, strangers are *silently ignored* (no pairing code) — by design
   (authz_mixin.py:700-706, #9337).

## Traps that cost real time here — read before changing anything

1. **Untracked files are invisible to the evaluator.** Local flakes resolve from
   the git tree; a new file must be `git add`ed before `nix eval` sees it.
2. **Editing a `vars/generators/*.nix` invalidates its persisted prompt value**
   (the var id hashes the generator). The next deploy re-prompts for it and, with
   no TTY, dies with `termios.error: Inappropriate ioctl`. Drive prompts through
   a pty if you must (I used `/tmp/pty-answer-empty.py`, which answers every
   prompt with an empty line).
3. **`secret = false` on a generator file makes it a value, not a deployed
   file** — it never lands in `/run/secrets`, and `my.secrets.getValue` then
   makes eval fail on a fresh clone until `clan vars generate` has run. Don't mix
   it with a runtime install unit.
4. **`my.secrets.allowReadAccess` builds ONE ACL unit per path.** Two entries for
   the same file (from two modules) collide and one is dropped silently. Put all
   readers in one entry; `signal-cli.nix` now asserts this at eval.
5. **`RemainAfterExit = true` + a path unit = runs once, ever.** Path units
   activate with `systemctl start`, which is a no-op on an active oneshot.
6. **tmpfiles rules only run at boot**, and `d` does not adjust an existing
   directory (you need `D`). Worse: the NixOS `users-groups` activation chowns
   managed homes *after* your unit runs, so "chown the home to root" cannot win.
   The `agent` account therefore has **no home at all** (`/var/empty/agent`,
   `createHome = false`).
7. **Path watches vs `/run/secrets`**: Clan re-mounts that tmpfs with
   `bind --beneath` every deploy, so a *directory* watch (`PathChanged`) fires
   per sibling file and can trip `trigger-limit-hit`. Watch the file
   (`PathModified`), and install at activation as well. (The concurrent charon
   session has an unstaged rework of exactly this in `agent-ssh-access.nix`.)
8. **`ssh-keygen -y` refuses to read a group/world-readable private key** and
   exits 255. The build sandbox hands you 0644, so `chmod 0400` first, or just
   `mv` the `.pub` ssh-keygen already wrote (what `wake-proxy-keep-awake-ssh`
   does). This broke the "generate a fresh keypair" path entirely.
9. **`nix fmt` and the treefmt check disagree** on `{pkgs, ...}: {` (different
   alejandra versions: devshell vs `config.treefmt.build.wrapper`). If the check
   fails on formatting that `nix fmt` called clean, hand-fix and re-run.
10. **A provider release package needs the right JDK.** signal-cli 0.14.8's
    classes are class-file version 69 → `jdk25_headless`, not nixpkgs' default
    `jdk` (21).
11. **A literal glob in `makeWrapper --add-flags` is expanded when the wrapper is
    written**, so java receives the expansion and the next flag becomes the main
    class. Build a concrete classpath in `installPhase`.
12. **`Restart = "always"` + a permanent config error = a 6/minute loop.**
    Bounded backoff (`RestartSteps`, `RestartMaxDelaySec`) plus a start-on-rotation
    restarter.

## Paths on makemake

```
/var/lib/hermes/            state root — restic job "hermes", b2, daily
  .hermes/.env              provider + Signal creds, re-rendered on rotation
  .hermes/config.yaml       rendered from Nix settings
  .hermes/state.db          sessions + memory (SQLite)
  home/.ssh/id_ed25519      fleet SSH identity
  home/.ssh/known_hosts     github + io + charon + makemake
  workspace/                the agent's working directory (empty so far)
/var/lib/agent-work/        writable scratch for the `agent` SSH account
/var/lib/signal-cli/        Signal account + session, 0700 signal-cli:signal-cli
/etc/ssh/authorized_keys.d/agent   root:root 0444, `restrict` prefix
```

`state.db` runs in `journal_mode=DELETE`, not WAL: nixpkgs 26.05 ships SQLite
3.51.2, below the 3.51.3 that fixed the WAL-reset bug, so Hermes disables WAL
itself. That is why the restic job takes a `sqlite3 .backup` snapshot (with an
`[ -f ]` guard — `sqlite3 missing.db ".backup …"` creates a root-owned file and
would lock the `hermes` user out of its own database).

## Operations

```bash
clan machines update makemake --host-key-check accept-new   # deploy
systemctl status hermes-agent signal-cli
journalctl -u hermes-agent -f
curl -s 127.0.0.1:8085/api/v1/check                         # signal-cli health
docker exec hermes-agent /data/current-package/bin/hermes chat -q '…'   # one-shot agent run
clan vars set --machine makemake hermes-env/env             # rotate creds
```

Sanity check after any change: the agent should answer through commandcode, and
`ss -tn | grep :8085` should show the SSE socket.

**Never** `git add -A` here: a concurrent session works in this tree. Stage
explicit paths. (I did `git add -A` for most of a session and swept three
unrelated files — `secondary-user-password.nix`, `session-dispatch.nix`,
`niri-config.kdl` — into my index. They were committed separately by the user
afterwards.)

## Open work, ranked

1. **Repos in front of the agent.** Never implemented: a `systemd` timer doing
   `git fetch` of `infra` + `homelab` into `/var/lib/hermes/workspace`, so the
   agent reads locally instead of over SSH and pushes branches instead of
   touching the owner's checkouts. This is the original "knowledge and
   collaboration" requirement and the biggest remaining gap.
2. **Deploy charon / io / ariel.** They have the `agent` account and ACLs in
   their evaluated config but have not been redeployed since. `charon` matters
   most (repo access: `traversePaths = ["/home/p"]`, `readablePaths =
   ["/home/p/repos"]` via setfacl — `/home/p` is 0700, so without those ACLs the
   agent cannot reach the repos at all). Never *tested*: the ACL behaviour is
   verified by generated script only, not by a real read as `agent`.
3. **Mail + calendar.** `agent@<domain>` on the existing `mailserver` module
   (private-infra input), then IMAP/SMTP creds into `hermes-env`.
4. **Web UI, undecided.** Open WebUI is already on makemake and speaks the
   protocol the agent's API server exposes: `API_SERVER_ENABLED=true` +
   `API_SERVER_KEY=…` in `hermes-env`, then point Open WebUI at
   `http://127.0.0.1:8642/v1`. Two lines, no new units. The native Hermes
   dashboard is impossible in container mode (assertion #5 above); running
   `hermes dashboard` as a second process inside the container is possible
   (prebuilt `web_dist` is already on the ro `/nix/store` mount) but is a process
   the upstream module refuses to manage.
5. **In-flight, needs review:** the unstaged `agent-ssh-access.nix` path-unit
   rework from the charon session (Install-then-watch). It supersedes the
   `PathExists`/`PathChanged` pair in `e4660d4`; the reasoning about
   `bind --beneath` trigger churn is sound and should be committed after review.
6. **Tier-B SSH scoping** — a forced command per host wrapping a read-only
   allowlist, once real usage patterns are known. Deliberately not built.
7. **Rotation watcher for signal-cli alone**: covered by the shared
   `hermes-env-rotation` unit already, so no separate watcher is needed.

## State at handoff

- HEAD `e4660d4 feat(agent): commandcode provider, signal-cli 0.14.8, ssh installer fixes`.
  A clean checkout of HEAD passes `nix flake check`.
- Working tree has exactly one unstaged modification:
  `modules/system/agent-ssh-access.nix` (the concurrent session's path-unit
  rework). It is **not deployed**; makemake runs the committed version.
- `agent verify full` → exit 0 (`.agent/runs/2026-10-01T134834+0200-full`),
  `agent guard check` → exit 0 (2 warnings, none forbidden).
- Secrets: `hermes-env` and `agent-ssh-key` are generated; var values are
  committed **age-encrypted** (`ENC[AES256_GCM,…]`) and the repo
  `perstarkse/infra` is **public**, so nothing sensitive may enter plaintext in
  git. The Signal number is never a Nix value — it is read from `SIGNAL_ACCOUNT`
  at unit start, and the same file feeds both the daemon and the agent.
- Known environment quirks worth remembering: nixpkgs' signal-cli 0.14.2 cannot
  link (that is why `pkgs/signal-cli` exists); `/bin/bash` does not exist on
  NixOS; `clan ssh -c` execs one binary.