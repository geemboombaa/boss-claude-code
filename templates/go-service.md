# [PROJECT NAME] — CLAUDE.md

## What This Is
[2 sentences: product, users, value]

## Tech Stack
- Language: Go 1.22+
- Framework: [net/http | Gin | Chi | Fiber]
- DB: [PostgreSQL | SQLite]
- Test runner: go test
- Linter: golangci-lint

## Phase Plan
- Phase 1: Domain types + interfaces
- Phase 2: Business logic + unit tests
- Phase 3: HTTP handlers + integration tests
- Phase 4: E2E + benchmarks

## Hard Rules — Non-Negotiable
- Invoke /tdd proactively for every non-trivial implementation
- Do not report success until Stop hook passes
- Run /verify before every "done" claim
- Run /certify before every "complete" claim
- No global state
- Errors wrapped with context: `fmt.Errorf("pkg/func: %w", err)`
- Table-driven tests for all business logic
- All interfaces defined in the package that uses them, not the package that implements them

## Session Start Protocol
1. Read this file completely
2. `git log --oneline -10`
3. `go test ./...` — confirm green
4. If red: fix first
5. Check open Issues / PRs first

## Where To Look When...

| Question | Look here |
|---|---|
| Domain types? | `internal/domain/` |
| Service logic? | `internal/service/` |
| HTTP handlers? | `internal/handler/` |
| Tests? | `*_test.go` co-located with source |
| Run tests? | `go test ./... -v` |
| Run server? | `go run ./cmd/server` |
