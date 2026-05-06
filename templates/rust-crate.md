# [PROJECT NAME] — CLAUDE.md

## What This Is
[2 sentences: product, users, value]

## Tech Stack
- Language: Rust (edition 2021)
- Framework: [Axum | Actix-web | none]
- DB: [sqlx + PostgreSQL | rusqlite]
- Test runner: cargo test
- Linter: clippy

## Phase Plan
- Phase 1: Core types + traits
- Phase 2: Business logic
- Phase 3: API / CLI interface
- Phase 4: Integration + property tests

## Hard Rules — Non-Negotiable
- Invoke /tdd proactively for every non-trivial implementation
- Do not report success until Stop hook passes
- Run /verify before every "done" claim
- Run /certify before every "complete" claim
- No `.unwrap()` in production code — use `?` or explicit error handling
- No `clone()` without justification in hot paths
- `cargo clippy -- -D warnings` must pass

## Session Start Protocol
1. Read this file completely
2. `git log --oneline -10`
3. `cargo test` — confirm green
4. `cargo clippy -- -D warnings` — confirm clean
5. If red: fix first
6. Check open Issues / PRs first

## Where To Look When...

| Question | Look here |
|---|---|
| Core types? | `src/types.rs` or `src/domain/` |
| Business logic? | `src/lib.rs` or `src/service/` |
| Tests? | `#[cfg(test)]` modules co-located, plus `tests/` for integration |
| Run tests? | `cargo test` |
| Benchmarks? | `benches/` |
