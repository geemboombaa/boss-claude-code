# [PROJECT NAME] — CLAUDE.md

## What This Is
[2 sentences: product, users, value]

## What This Is NOT
- [Explicit exclusions]

## Tech Stack
- Language: Node.js 20+
- Framework: [Express | Fastify | Hono]
- DB: [PostgreSQL | SQLite | MongoDB]
- ORM: [Prisma | Drizzle | Mongoose]
- Package manager: npm / pnpm
- Test runner: [Jest | Vitest]
- E2E: Playwright (if applicable)
- Linter: ESLint + Prettier

## Phase Plan
- Phase 1: Data layer (schema, migrations, seed)
- Phase 2: Business logic (services)
- Phase 3: API (routes, middleware, auth)
- Phase 4: Integration + E2E tests

## Hard Rules — Non-Negotiable
- Invoke /tdd proactively for every non-trivial implementation
- Do not report success until Stop hook passes
- Run /verify before every "done" claim
- Run /certify before every "complete" claim
- Write tests FIRST, code second
- No `any` types in TypeScript
- Use `async/await` not `.then()` chains
- All DB queries go through the ORM, never raw SQL without parameterization

## Session Start Protocol
1. Read this file completely
2. Run: `git log --oneline -10`
3. Run: `npm test` — confirm green before touching anything
4. If red: fix first, commit, THEN work on new requirements
5. Check open Issues / PR comments first
6. If no explicit requirement: ask "what is the goal this session?"

## Where To Look When...

| Question | Look here |
|---|---|
| Route definitions? | `src/routes/` |
| Business logic? | `src/services/` |
| DB schema? | `prisma/schema.prisma` or `src/db/` |
| Tests? | `tests/` or `src/__tests__/` |
| Run tests? | `npm test` |
| Run server? | `npm run dev` |
| Env vars? | `.env.example` |
