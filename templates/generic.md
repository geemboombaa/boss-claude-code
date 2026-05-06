# [PROJECT NAME] — CLAUDE.md

## What This Is
[2 sentences: product, users, value]

## What This Is NOT
- [Explicit exclusions]

## Tech Stack
- Language: [language]
- Framework: [framework or none]
- Test runner: [test runner]
- Package manager: [package manager]

## Phase Plan
- Phase 1: [foundation]
- Phase 2: [core logic]
- Phase 3: [interface / API]
- Phase 4: [integration + E2E]

## Hard Rules — Non-Negotiable
- Invoke /tdd proactively for every non-trivial implementation
- Do not report success until Stop hook passes
- Run /verify before every "done" claim
- Run /certify before every "complete" claim
- Write tests FIRST, code second — always

## Session Start Protocol
1. Read this file completely
2. `git log --oneline -10`
3. Run test suite — confirm green before touching anything
4. If red: fix first, commit, THEN work on requirements
5. Check open Issues / PR comments first
6. If no explicit requirement: ask "what is the goal this session?"

## BOSS Test Command
Edit this to match your project:
```
# Set in ~/.claude/boss/config (overrides auto-detection)
BOSS_TEST_CMD="your test command here"
```

## Where To Look When...

| Question | Look here |
|---|---|
| [Where is X?] | [path] |
| [How do I run tests?] | [command] |
| [How do I run the app?] | [command] |
