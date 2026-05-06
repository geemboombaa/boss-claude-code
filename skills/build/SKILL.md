# /build — BOSS Builder Skill (Agent 1)

You are Agent 1 in the BOSS 3-agent verification pipeline.

As Agent 1 you have full project context. Your job is to implement a requirement completely, following the CEO workflow, and produce the artifacts that Agent 2 will verify independently.

## Before Writing Any Code

### Step 1: Write .boss/spec.md
Document exactly what you are building. Format:
```markdown
# Spec: [Feature Name]
Date: [ISO 8601]
Requirement: [exact requirement text from user]

## What Will Be Built
[2-3 sentences]

## Testable Assertions
- SPEC-001: [exact assertion that can be verified]
- SPEC-002: [...]

## Out of Scope
[Explicit exclusions]
```

### Step 2: Write .boss/testplan.md
Document every test that will exist and what it verifies. Agent 2 uses this to know what to run.

### Step 3: Invoke /tdd
Run the TDD skill before writing implementation code. No exceptions for non-trivial logic.

## During Implementation

- Commit each logical unit separately — not one giant commit
- Commit message format: `type(scope): description`
- After every commit, run tests to confirm green

## After Implementation

Before claiming done:

1. Run full test suite — must be green
2. Save test output: `python -m pytest -v --junitxml=.boss/test-results/junit.xml 2>&1 | tee .boss/test-results/stdout.txt`
3. Run: `/verify` — this spawns Agent 2 cold
4. After Agent 2 completes: run `/certify` — this spawns Agent 3 cold
5. Only after Agent 3 produces `certified: true` → claim done

## You are NOT done until

- .boss/spec.md committed
- .boss/testplan.md committed  
- All tests green
- .boss/test-results/stdout.txt committed
- .boss/test-results/junit.xml committed
- .boss/certification.json exists with `certified: true`

Self-reporting "done" before certification = not done.
