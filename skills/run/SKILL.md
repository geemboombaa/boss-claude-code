# /run — CEO Walkaway Orchestration

**You are executing autonomously. CEO has walked away.**
**Do NOT ask questions or stop responding except for the explicit conditions below.**

---

## STOP CONDITIONS — only these, nothing else

1. **Design decision** — two valid architectures with different scope, cannot choose without CEO
2. **Business decision** — cost, priority, scope change beyond the stated requirement
3. **External blocker** — credentials/API keys you cannot obtain

For everything else: make the reasonable call, document it in `.boss/run-plan.md`, keep going.

---

## Entry — run this sequence every time /run is invoked

**E1** — Read resume state:
- Use `Read` tool on `.boss/run-plan.md` (ignore if file does not exist)
- If `last_completed_phase` exists, skip to the NEXT phase
- If not, start from Phase 1

**E2** — Write/update run-plan:
- Use `Write` tool on `.boss/run-plan.md`:
  ```
  status: running
  started_at: <ISO timestamp>
  last_completed_phase: null
  ```

---

## Phase 1 — parse requirement

**Goal:** Extract structured understanding BEFORE touching the codebase. Research is only useful if targeted.

**Tools:** `Read`, `Write`

1. Use `Read` on `CLAUDE.md` — get full requirement text
2. Extract and write to `.boss/run-plan.md`:
   - `requirement`: verbatim first requirement line
   - `keywords`: 3-6 searchable terms (function names, module names, domain concepts)
   - `entities`: files/modules likely affected
   - `change_type`: new feature | bug fix | refactor | config change
3. If requirement is ambiguous with two meaningfully different scopes → **STOP, ask CEO one question**
4. Use `Write` to create `.boss/parsed-requirement.md`:
   ```
   # Requirement
   <verbatim text>

   ## Keywords for search
   - <keyword 1>
   - <keyword 2>
   ...

   ## Expected change
   <one sentence: what will be different after this is built>

   ## Files likely affected
   - <file or module>
   ...
   ```

Update `.boss/run-plan.md`: `last_completed_phase: parse`

---

## Phase 2 — research (targeted, not blind)

**Goal:** Find exactly what exists in the codebase that relates to the parsed requirement.

**Tools:** `Read`, `Glob`, `Grep`, `Bash`, `Write`

1. Use `Read` on `.boss/parsed-requirement.md` — get keywords and entities
2. For each keyword: use `Grep("<keyword>", output_mode="files_with_matches")`
3. Use `Glob` to find files matching entity names from parsed-requirement
4. Use `Bash("git log --oneline -15")` for recent context
5. Use `Read` on 2-4 most relevant files found above
6. Use `Write` to create `.boss/research.md`:
   - What exists that relates to this requirement
   - What is missing
   - Edge cases and risks
   - Relevant file paths

Update `.boss/run-plan.md`: `last_completed_phase: research`

---

## Phase 3 — spec

**Tools:** `Read`, `Write`

1. Use `Read` on `.boss/parsed-requirement.md` and `.boss/research.md`
2. Use `Write` to create `.boss/spec.md`:
   ```markdown
   # <requirement title>

   ## Acceptance Criteria
   1. <testable criterion>
   2. <testable criterion>
   ...

   ## Out of Scope
   - <explicitly excluded>

   ## Dependencies
   - <files/services affected>
   ```

Update `.boss/run-plan.md`: `last_completed_phase: spec`

---

## Phase 4 — testplan

**Tools:** `Read`, `Write`

1. Use `Read` on `.boss/spec.md`
2. Use `Write` to create `.boss/testplan.md` — one entry per acceptance criterion:
   - Test name
   - Type: unit / integration / e2e
   - Input + expected output

Update `.boss/run-plan.md`: `last_completed_phase: testplan`

---

## Phase 5 — TDD red

**Tools:** `Read`, `Write`, `Bash`

1. Use `Read` on `.boss/testplan.md`
2. Use `Write` to create test file — implement ALL tests from testplan
3. Use `Bash` to run tests — they MUST fail here (red = correct)
   ```bash
   python -m pytest tests/test_<slug>.py -v --tb=short
   ```
4. If tests pass without implementation: tests are wrong — fix until they fail
5. Use `Bash` to commit:
   ```bash
   git add tests/test_<slug>.py
   git commit -m "test: <requirement slug> — red phase"
   ```

Update `.boss/run-plan.md`: `last_completed_phase: tdd`

---

## Phase 6 — code (green)

**Tools:** `Read`, `Write`, `Edit`, `Bash`

1. Use `Read` on test file and spec
2. Implement — write only what makes tests pass
3. After each change: `Bash("python -m pytest tests/test_<slug>.py -v")`
4. Iterate until ALL tests pass
5. Commit each file: `Bash("git add <file> && git commit -m 'feat: <what and why>'")`

Update `.boss/run-plan.md`: `last_completed_phase: code`

---

## Phase 7 — verify (truly independent process)

**IMPORTANT: Do NOT use the Agent tool here. Agent tool subagents share session context with you.
Verification must be adversarial — Agent 2 has zero knowledge of what you built or how you built it.
Spawn a completely separate OS process using Bash.**

**Tools:** `Bash`

```bash
cd <project_cwd> && claude -p "/verify"
```

This runs a completely separate `claude` process. Agent 2:
- Has no access to this conversation
- Has no access to your context
- Reads ONLY files on disk: `.boss/spec.md`, `.boss/testplan.md`, test results
- Runs tests independently
- Writes `.boss/verification.md`

Wait for `Bash` to return. Then use `Read` on `.boss/verification.md` to confirm it was written.

Update `.boss/run-plan.md`: `last_completed_phase: verify`

---

## Phase 8 — certify (truly independent process)

**Same rule: separate OS process, zero context from builder.**

**Tools:** `Bash`

```bash
cd <project_cwd> && claude -p "/certify"
```

Agent 3:
- Reads ONLY `.boss/spec.md` and `.boss/verification.md`
- Writes `.boss/certification.json`
- certified=true only if ALL acceptance criteria show PASS in verification.md

After Bash returns: use `Read` on `.boss/certification.json`.
If `certified: false` → return to Phase 6, fix gaps listed in `gaps[]`.

Update `.boss/run-plan.md`: `last_completed_phase: certify`

---

## Phase 9 — commit artifacts

**Tools:** `Bash`

```bash
git add .boss/parsed-requirement.md .boss/research.md .boss/spec.md \
        .boss/testplan.md .boss/verification.md .boss/certification.json \
        .boss/run-plan.md
git commit -m "chore: BOSS artifacts — <requirement slug>"
```

Update `.boss/run-plan.md`: `last_completed_phase: commit`

---

## Phase 10 — push + PR

`auto-push.ps1` PostToolUse hook fires automatically after `git commit`.
`auto-pr.ps1` fires automatically after push.

If hooks did not fire:
```bash
git push -u origin HEAD:boss/<slug>
powershell -ExecutionPolicy Bypass -File hooks/auto-pr.ps1
```

Update `.boss/run-plan.md`:
```
last_completed_phase: pr
status: complete
```

---

## Done

CEO receives `BOSS_NOTIFY` webhook when CI finishes.
CEO opens PR → green badge + `certification.json` certified by a process that had zero access to the builder's context.
