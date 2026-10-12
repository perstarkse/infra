# Roadmap (ephemeral): p × agent collaboration

How the owner (`p`) and the fleet agent (`agent`) work together: identity,
authorship, push/deploy flow, shared space, secrets/MCP. Status: design only,
nothing below is implemented. Delete this file once folded into durable docs.

## Decisions

| # | Decision |
|---|---|
| C1 | Committer is always `Per Stark <per@stark.pub>`. Agent work sets author to `agent <agent@stark.pub>` and signs with a dedicated signing-only key — with the GitHub-verification caveat below. |
| C2 | **One** write-capable account-level SSH auth key for agent (`agent-git-auth`), accepted with the all-repos blast radius below. Agent pushes to main. No branch protection. |
| C3 | Deploy loop runs in a p pane with agent attached (agent prepares/verifies, p's keystroke invokes) — with the honesty caveats below. No technical deploy gate; green read-only gates + practiced revert instead. Agent keeps no path to root (no root keys, no ForwardAgent, out of wheel). |
| C4 | Rename `repos` → `projects`: `/home/p/projects` and `/home/agent/projects` both symlink to `/mnt/sdb/repos`; keep `/home/p/repos` compat link through transition. Agent reaches the tree via `/mnt/sdb/repos` or its own symlink — never by traversing `/home/p`. |
| C5 | `/home/p` → 700 with **zero** agent ACLs (verified: `--x` + world-readable dotfiles already leaks). `/home/agent` → 750 with `u:p:r-X`, `projects` created 0750. `/mnt/sdb/repos` gets access **and** default ACLs for both principals with write (`u:agent:rwX,u:p:rwX`), applied recursively to existing checkouts. |
| C6 | Agent gets use access to all MCP servers: sops reader grants for key-based ones; **separate** OAuth token stores per principal (shared stores race on refresh); own provider-auth caches. Inventory rule replaces the promotion rule. |
| C7 | p's herdr server = supervision plane; agent's server = execution plane. Agent code runs in agent panes; p panes host p (plus explicitly scoped agent assistance, with the uid-1000 honesty note below). Revoke agent's rw on p's herdr socket. Web-UI auth (D6) becomes the lock on this topology. |

## C1 — Authorship and keys

- Committer: `Per Stark <per@stark.pub>`, always, both principals. Ownership is never ambiguous.
- Author: whoever produced the content (`agent <agent@stark.pub>` for agent work, via `GIT_AUTHOR_*` in agent's shell/herdr-pane env). `git shortlog` and forge UIs attribute correctly.
- `agent-git-auth` (auth key, account-level, write): push/pull/fetch. Registered once on GitHub by p. **Blast radius if leaked (agy review): every repo p can access, not just infra** — accepted deliberately (one key for ~40 repos beats 40 deploy keys), mitigated by: no deploy creds on the key, no branch protection to bypass, deploy still needs p's pane. Narrow to per-repo deploy keys only if a repo ever needs it.
- `agent-git-sign` (signing key only): `gpg.format = ssh`, `commit.gpgsign = true` in agent's HM git config; public half registered as GitHub *signing* key. Cannot auth to anything; leak forges attestation only.
- `gpg.ssh.allowedSignersFile` carries the *signing* keys only (never auth keys), with explicit principal lines (`agent@stark.pub` → agent key, `per@stark.pub` → p key) so local verification maps email to key correctly.
- Reading a commit: committer = who stands behind it (always p); author = whose judgment produced it; signature = which key attested it. Agent-signed + p-committed = "agent produced, p owns". Unsigned where signing is configured = anomaly.
- **GitHub-verification caveat (agy review):** GitHub matches the signature against the *committer* email, so an agent-signed + p-committed commit shows Verified-as-p (attribution lives in the author field and `git log --show-signature` locally, not in GitHub's badge). Accept: the badge was never the audit trail — `author` + local signature verification is. If GitHub badges ever matter, the fallback is a separate machine-user account owning the signing key.

## C2/C3 — Push flow and deploy gate

- Agent pushes to main directly. No PR ceremony, no branch protection: p would be the merger anyway, and `machine-update` (p-invoked) is the real gate.
- Read-only CI on main is the backstop (treefmt, eval, VM tests); a red main is immediately visible, fixed forward with `git revert` + redeploy.
- Deploy loop preserved: agent does eval/check/plan/diagnose autonomously; the mutating `machine-update <hosts>` runs in a p pane with agent attached (watching output, proposing fixes). Only added step vs today: p's keystroke on the mutating command.
- **Honesty caveats (agy review, verified):** "which pane" is convention, not enforcement — herdr does not authenticate typed-vs-injected input, and agent holds **rw on p's herdr socket today** (`user:agent:rw-` on `/home/p/.config/herdr/herdr.sock`, verified via getfacl), so pane injection is already possible. Mitigations in this design: revoke that socket grant (agent drives p's server only via explicit `herdr --machine` over SSH, never ambient socket rw); additionally `forwardAgent = true` on charon + fleet `deploy.forwardAgent` means any agent inside a p-pane context inherits `SSH_AUTH_SOCK` reaching root fleet-wide — so agent assistance inside p panes must run with a scrubbed env (no `SSH_AUTH_SOCK`) as well as scoped cwd. The residual claim is then honest: the gate is p's keystroke + full session audit trail, against an agent that *could* technically bypass it but is configured not to — same trust model as p's own shell history.
- Agent never holds a path to root of its own: no root SSH keys in agent's home, no `ForwardAgent` toward agent, agent out of `wheel` (all true today — kept true by absence).
- No wrapper scripts or clan ACLs as gates: bypassable by the constrained principal, or they kill the verify-fix loop. Revisit only when a real incident names the missing property.

## C4/C5 — Shared space and visibility

```
  /home/p/          700 p:users, zero agent ACLs — p-private, full stop
    projects -> /mnt/sdb/repos
    repos -> /mnt/sdb/repos       — compat link, remove after cooling period (~1 month)
  /home/agent/      750 agent:agent + u:p:r-X — p reads everything downhill
    projects -> /mnt/sdb/repos   — same tree, viewed from here
    scratch/                     — agent-private experiments (still p-visible)
  /mnt/sdb/repos    750 p:users + access+default ACLs u:agent:rwX, u:p:rwX (recursive)
```

- **Why zero agent ACLs on `/home/p` (agy blocker, verified):** `/home/p` is 710 today with `user:agent:--x`, and world-readable dotfiles (`deimos.sh`, `.python_history`, `.wget-hsts`, … — verified via find) are already open to agent through it. `--x` without listing still allows opening any known/guessable path. The compat `repos` symlink is no excuse to keep it: agent reaches the tree via `/mnt/sdb/repos` (canonical) or `/home/agent/projects`, never through `/home/p`. Drop the traverse grant entirely with the cutover; `/home/p` becomes pure 700.
- **Write, not read (agy blocker, verified):** agent commits and pushes in this tree, so `r-X` breaks `git commit`/`checkout -b` with EACCES. Grants are `rwX` for agent *and* `rwX` for p (else p can't touch agent-created files). `-R` recursive application covers existing checkouts; `-d` default covers new clones. `agent-path-acl.service` learns both.

- Physical paths never move: pi sessions (`--mnt-sdb-repos-*`), herdr `session.json` cwds, git worktree backpointers all survive.
- Nix updates: `readablePaths`, `pi-web.pathAccess.allowedPaths`, `permissions.external_directory` entries gain `projects` variants (keep `repos` variants through transition).
- `agent-path-acl.service` learns `-d` (default) **and** `-R` (recursive) ACL application for `readablePaths`; `agent-workdir.service` creates `${home}/projects` 0750 (not 0700) so p's read grant actually reaches inside.
- direnv migration rides the cutover: 129 allow-files keyed by literal path; bulk `direnv allow` per checkout in the same session as the symlink switch.
- Verify `users`-group nothing needs `/home/p`'s group-X bit before 710 → 700.

## C6 — Secrets and MCP

Rule: **Nix manages file placement and ACLs; humans do browser clicks once; agents never mint credentials.**

- New sops generators (one-time setup, then zero-touch): `agent-git-auth` and `agent-git-sign` private halves, `readers = [agent]`, `0400` into `/home/agent/.ssh`. Public halves registered on GitHub by p (imperative, once).
- Reader grants on existing generators: `context7`, `accounted-mcp-key` add agent to readers. The `!command` header pattern in `mcp.json` is unchanged — agent's pi reads the same `/run/secrets` paths via its own grant.
- OAuth/browser-consent servers (digikey, onshape): **separate token stores per principal (agy blocker).** Shared stores race on refresh-token rotation (one principal's refresh invalidates the other's) and the writer needs write access the reader-grant can't give. So: p keeps `DIGIKEY_TOKEN_STORE` under `/home/p/.local/state` (outside agent's reach entirely); agent gets its own consent flow once, token store under `/home/agent/.local/state`. Same account upstream is fine (p's lists stay p's lists); the *files* must not be shared. Separate consent only if agent starts owning distinct documents/lists — the stores are already separate either way.
- Provider auth (pi/antigravity LLM keys): separate caches under `/home/agent` (already true by HOME); p-readable via the 750 change. Spend attributes to agent.
- Promotion rule replaced by inventory rule (agy warning): **every credential agent can read is declared in Nix** (sops grant, ACL resource, or token-store path) — no uninventoried files in `~/.pi`/`~/.config` that rotation forgets. Bucket C (imperative files) still exists for speed, but each entry is a line in a Nix list with an owner and a rotation story, not an undocumented file.

## C7 — Supervision topology

- p's server: supervision plane (p's panes, p's UI tab). Agent tasks driven here run as uid 1000 — **no logical containment is claimed** (agy warning, accepted): a pane process can read `~/.ssh/id_ed25519`, the mesh key, and the sops age key straight off disk regardless of env scrubbing. Scoping inside p panes is therefore *social* (cwd = shared tree, ask-first pi profile, short-lived assistance) plus the SSH_AUTH_SOCK scrub above — never a security boundary. Anything that must be contained runs in agent's panes.
- Agent's `rw` on p's herdr socket is revoked (see C3): cross-driving goes over SSH (`herdr --machine`), explicitly, every time.
- Agent's server: execution plane (long runs, loops, mesh driving). p attaches read-mostly, intervenes by explicit input. Cross-driving via `herdr --machine` is always explicit.
- Crossing rule: agent code runs in agent panes; results land in the shared tree as signed, trailered commits or resumable session handoffs.
- Web-UI auth (was D6-deferred) graduates to the lock on this design: token-gate the makemake UI so the supervision plane is enforceable, not conventional.

## Sequencing

1. Git keys + agent git config (C1: two generators, HM stanza, GitHub registrations). Self-contained; everything downstream assumes it.
2. Permission fixes + symlinks + Nix updates + direnv re-allow (C4/C5). Includes: drop agent traverse on `/home/p`, socket-grant revocation, `agent-workdir` 0750, recursive+default ACL application.
3. MCP reader grants + separate agent OAuth stores (C6, key-based first, agent consent flows second).
4. Web-UI token gate (C7 lock). Deploy-loop practice (revert drill) alongside.

## Review record

- agy second-opinion review, 2026-10-12: 5 blockers, 8 warnings, 2 nits. Integrated: GitHub committer-vs-signer caveat, zero-ACL `/home/p` (traversal leak verified), rwX+recursive+default ACLs, separate OAuth stores, pane-gate honesty + socket revocation + SSH_AUTH_SOCK scrub, account-key all-repos blast radius, allowed_signers principal mapping, forwardAgent inheritance, uid-1000 containment honesty, inventory-over-promotion rule, `projects` 0750 creation, direnv ordering, `users`-group audit note. Rejected: nothing — all findings verified against the live system before integration.
