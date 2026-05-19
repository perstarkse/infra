# Agentic Development Guidelines

## Testability & Verification

- **Test-First Mindset**: All new implementations MUST include a plan for testing.
- **Mandatory Tests**: No implementation is complete without tests.
- **Run Before Finish**: You MUST run all relevant tests and ensure they pass before marking a task as complete.
- **Self-Correction**: If tests fail, use the failure output to correct your code immediately.

## Quality Gates

- **Nix**: Run `nix flake check` after any module or flake change.
- **Rust**: Run `cargo test`, `cargo clippy`, and `cargo fmt --check` in the repo root.
- **Frontend**: Run `pnpm run lint`, `pnpm run type-check`, `pnpm test` from the frontend directory.
- **Infra deploy**: Run `exposure-manifest-check` for domain/DNS conflicts before deploying router changes.

## Snapshots

- Prefer `cargo insta` commands when snapshot output changes intentionally:
  - `cargo test` to generate/confirm snapshot updates
  - `cargo insta review` or `cargo insta accept` to accept reviewed changes
- If `cargo-insta` is unavailable, review `.snap.new` files manually before promoting to `.snap`.

## Global Principles

- **Smallest viable change**: Favor straightforward code, single-file diffs when possible. KISS/YAGNI.
- **Rule-of-three**: Only add new traits/helpers/abstractions after the same pattern appears 3+ times or a spec demands it.
- **Complexity triggers**: Avoid new crates/deps unless required by spec/design. Keep control-flow shallow. Split files only when truly too large.
- **Scope discipline**: Touch only what the task/spec calls for. No surprise refactors, migrations, or deployment changes.
- **Prefer reuse**: Search existing code before adding helpers or dependencies.

## Workflow Precedence

If instructions conflict, use this order:
1. Explicit user request for the current command/workflow
2. Managed OpenSpec workflow steps in the prompt
3. Project-level standing rules in this file

## Push Policy

- Do NOT push unless the user explicitly asks.
- Do not block task completion on push.
- Clearly report push state (e.g. branch ahead of origin) when handing off.

## Landing the Plane (Session Completion)

When ending a work session:
1. **File issues** for remaining work
2. **Run quality gates** (tests, linters, builds)
3. **Update issue status** — close finished, update in-progress
4. **Clean up** — clear stashes, prune remote branches
5. **Verify** — all changes committed locally, quality gates green
6. **Hand off** — provide context for next session, note push was not performed
