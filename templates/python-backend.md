# [PROJECT NAME] — CLAUDE.md

## What This Is
[2 sentences: what the product does, who uses it, what value it delivers]

## What This Is NOT
- Not a [competing product]
- Not responsible for [out-of-scope concern]
- [Explicit exclusion to prevent scope creep]

## Tech Stack
- Language: Python 3.12+
- Framework: FastAPI
- DB: [SQLite | PostgreSQL]
- ORM: SQLAlchemy (sync) / SQLModel
- Package manager: uv
- Test runner: pytest
- E2E: Playwright (if applicable)
- Linter: ruff

## Phase Plan
- Phase 1: Data layer (models, migrations, seed data)
- Phase 2: Business logic (services, domain rules)
- Phase 3: API (endpoints, auth, validation)
- Phase 4: Integration + E2E tests

## Hard Rules — Non-Negotiable
- Invoke /tdd proactively for EVERY non-trivial implementation (do not wait to be asked)
- Do not report success until Stop hook passes
- Run /verify before every "done" claim
- Run /certify before every "complete" claim
- Write tests FIRST, code second — always
- Use `uv run pytest` not bare `pytest`
- Never use `BigInteger` as primary key in SQLite (use `Integer`)
- Use `Integer` primary keys, not UUID, unless spec requires UUID
- TestClient as context manager: `with TestClient(app) as tc:`
- In-memory SQLite test DBs: session scope, not function scope
- Mock `create_tables()` in API tests to prevent real DB connections

## Session Start Protocol
1. Read this file completely
2. Run: `git log --oneline -10`
3. Run: `uv run pytest -q` — confirm green before touching anything
4. If red: fix first, commit, THEN work on new requirements
5. Check for open GitHub Issues or PR comments — those are priority
6. If no explicit requirement: ask "what is the goal this session?"

**Never start new work on a red test state.**

## Where To Look When...

| Question | Look here |
|---|---|
| How is the DB schema defined? | `app/models/` |
| Where are API endpoints? | `app/routers/` |
| Where is business logic? | `app/services/` |
| Where are tests? | `tests/` |
| How do I run tests? | `uv run pytest -q` |
| How do I run the server? | `uv run uvicorn app.main:app --reload` |
| What are the env vars? | `.env.example` |

## Test Conventions
- Unit tests: `tests/unit/`
- Integration tests: `tests/integration/`
- Fixtures in: `tests/conftest.py`
- Test DB: in-memory SQLite, session scope
- API tests: use `TestClient` as context manager

## Commit Convention
Conventional commits: `feat|fix|docs|test|refactor|chore(scope): description`
