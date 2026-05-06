# [PROJECT NAME] — CLAUDE.md

## What This Is
[2 sentences: product, users, value]

## What This Is NOT
- [Explicit exclusions]

## Tech Stack
- Backend: [FastAPI | Express | Next.js API routes]
- Frontend: [React | Vue | vanilla JS]
- DB: [PostgreSQL | SQLite]
- Test runner: [pytest | Jest | Vitest]
- E2E: Playwright
- Visual regression: Playwright toHaveScreenshot() + pixelmatch

## Phase Plan
- Phase 1: Data layer + backend API
- Phase 2: Frontend components (no E2E yet)
- Phase 3: Integration (connect frontend to API)
- Phase 4: E2E + visual regression tests

## Hard Rules — Non-Negotiable
- Invoke /tdd for every non-trivial unit
- Do not report success until Stop hook passes
- Run /verify before every "done" claim
- Run /certify before every "complete" claim
- ALL frontend changes require Playwright screenshot capture
- Visual diffs must be committed as artifacts before "done" claim
- Never claim "UI is done" without screenshot proof

## Visual Test Protocol
For every UI change:
1. Run: `npx playwright test --update-snapshots` (first run — establishes baseline)
2. On subsequent runs: `npx playwright test` — diffs auto-generated
3. Commit screenshots to `.boss/test-results/screenshots/`
4. Include screenshot paths in `/verify` invocation

## Session Start Protocol
1. Read this file completely
2. Run: `git log --oneline -10`
3. Run backend tests — confirm green
4. Run: `npx playwright test` — confirm E2E green (or document known failures)
5. If red: fix first
6. Check open Issues / PR comments first

## Where To Look When...

| Question | Look here |
|---|---|
| Backend routes? | `api/` or `backend/routes/` |
| Frontend components? | `src/components/` or `frontend/` |
| E2E tests? | `tests/e2e/` or `playwright/` |
| Visual snapshots? | `tests/e2e/__snapshots__/` |
| Unit tests? | `tests/unit/` |
| Playwright config? | `playwright.config.ts` |
