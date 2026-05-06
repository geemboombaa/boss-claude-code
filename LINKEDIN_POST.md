# BOSS — LinkedIn Post + Implementation Deep Dive

---

## LinkedIn Post

---

**I used Claude to build a system that forces Claude to do its job.**

Not metaphorically. Literally. I built an enforcement stack called BOSS — and I used BOSS to build BOSS.

Here's the problem I was solving.

---

### The Problem With AI Coding Agents

Claude Code is genuinely impressive. But it has a structural flaw that nobody talks about directly: **it has no enforcement layer.**

Claude will write tests, run them, get red, and then tell you "tests pass." Not lying exactly — it just has no mechanism that *forces* it to stay honest. The result? You become QA for your own AI assistant. You're the one catching regressions. You're the one re-running tests. You're the one asking "wait, did you actually verify that?"

I built BOSS to fix that permanently.

---

### What BOSS Is

**BOSS** (Build, Orchestrate, Supervise, Ship) is an enforcement stack for Claude Code.

4 layers. Each one closes a different gap:

**Layer 1 — Stop Hook (local gate)**
A shell script that runs before *every single Claude response*. If tests fail → Claude is blocked from responding. It receives its own failure output and must fix it. You never see a response where tests are red. Never. Mechanically enforced.

**Layer 2 — CEO Workflow (process gate)**
Defined division of labor. You write requirements. Claude does research → TDD → implement → commit. No back-and-forth managing. No "did you run tests?" You write one line. You come back to a green CI badge.

**Layer 3 — 3-Agent Verification Pipeline (quality gate)**
Every feature goes through three independent agents:
- **Agent 1 (Builder):** writes spec, testplan, code, tests. Has full context.
- **Agent 2 (Verifier):** zero context from Agent 1. Gets only the spec + git diff. Runs tests independently. Documents proof.
- **Agent 3 (Certifier):** zero context from either. Reads only spec + verification artifacts. Writes `certification.json`.

Work is not done until `certification.json` says `"certified": true`. Information isolation is structural — not enforced by trust, by what each agent *receives*.

**Layer 4 — CI (server-side gate)**
GitHub Actions on every push. Claude has zero control over it. Green badge = independently verified. The PR comment job posts BOSS certification status directly onto every pull request.

---

### The Part That Makes This Different

**I used BOSS to build BOSS.**

This isn't a humble brag — it's the validation. Here's what that actually looked like:

1. Wrote requirements in `.boss/requirements.md`
2. Told Claude: *"CEO walkaway mode. Come to me only for unclear requirements, blockers, business changes, and signoff."*
3. Claude ran the full pipeline: research → /build skill → TDD → implement → stop hook blocked failures → fix → verify (Agent 2) → certify (Agent 3) → commit
4. Came back to green CI. 88/88 requirements certified.

I wrote requirements. I said "agreed" at one signoff point. That was my contribution to the implementation.

---

### The Architecture

```
You write: "Add rate limiting. 1 req/4h per IP. 429 + retry-after."

Claude:
  → reads spec
  → /build skill: writes spec.md + testplan.md
  → writes tests first (TDD)
  → implements
  → stop hook fires: tests red → blocked
  → Claude fixes
  → stop hook: green
  → /verify: Agent 2 (zero context) runs tests, writes verification.md
  → /certify: Agent 3 (zero context) writes certification.json
  → git commit + push

You:
  → open GitHub
  → green CI badge
  → BOSS CERTIFIED comment on PR
  → review diff
  → merge
```

---

### What It Took to Build This

**88 requirements. 16 layers. 2 phases.**

Phase 1 (Layers 1-11):
- Stop hook: bash + PowerShell 5.1 (had to be compatible with Windows default shell, bash 3.2+ for macOS — no modern syntax)
- Install: one-liner curl | bash + PowerShell iwr | iex + npx
- 3-agent pipeline: skill files, isolation protocol, certification schema
- CLAUDE.md templates for 6 languages
- CI templates for 5 languages
- Git discipline hooks (conventional commits, pre-push gate)
- CI-first bootstrap (CI workflow pushed before any source code)
- Smart delta (diffs requirements.md vs git HEAD, only re-runs changed phases)
- Demo/signoff gate (blocks source writes until CEO approves demo artifacts)

Phase 2 (Layers 12-16):
- **Stop hook reliability:** `BOSS_RETRY=N` for flaky tests, `BOSS_SKIP_PATTERNS` for non-code changes (docs/config), `BOSS_WEBHOOK_URL` for push notifications on block events (ntfy.sh/Slack/Discord)
- **Test mutation protection:** `test-guard` PreToolUse hook writes a baseline of all test files at session start, blocks Claude from editing them — protects test integrity
- **Coverage pipeline:** `BOSS_COVERAGE=1` adds pytest-cov, `coverage_pct` field in certification.json, certifier extracts it
- **GitHub integrations:** PR comment job on all CI templates, BOSS certification status posted on every PR automatically
- **Windows/WSL hardening:** WSL detection in install.ps1, explicit `powershell.exe` path (prevents Git Bash routing to WSL)

---

### The Hard Engineering Problems

**1. YAML + Python heredoc incompatibility**
Tried to embed Python scripts as YAML literal block scalars. Python needs top-level statements at column 0 — YAML interprets column 0 content as block termination. Entire CI template test suite (10 tests) failed. Fix: `python3 -c "one-liner"` with semicolons. No f-strings (shell variable expansion would eat them).

**2. PowerShell 5.1 constraints**
Windows ships with PS5.1, not PS7. PS5.1 has no: ternary operator (`?:`), null-conditional (`?.`), `??` in some contexts, multi-line regex. Every hook had to work in PS5.1. Found a PS7-only ternary in test-guard.ps1 the night before ship — caught and fixed.

**3. Stop hook infinite loop**
Claude Code fires Stop hook before every response — including responses to stop hook failures. Without a guard, you get infinite loop: hook blocks → Claude tries to respond → hook fires again → repeat forever. Fix: check `stop_hook_active` in payload. Exit 0 immediately if true.

**4. Skills path discovery**
Claude Code auto-discovers skills at `~/.claude/skills/<name>/SKILL.md`. We were installing to `~/.claude/boss/skills/` — invisible to Claude. Found via research agent. All 5 skills relocated.

**5. Information isolation in 3-agent pipeline**
Agent isolation can't be enforced by "trust" — you have to control what each agent *receives*. Agent 2 gets spec.md + git diff. Not the conversation. Not Agent 1's context. Structurally isolated by what the prompt contains, not by hope.

---

### Why This Is Different From Every Other AI Productivity Tool

Most AI tooling is advisory. It suggests. It recommends. It adds personas.

BOSS *blocks*. The hook doesn't recommend that Claude fix tests. It prevents Claude from responding until tests pass. That's a different category of tool.

The 3-agent pipeline isn't "have Claude review its own code." Agent 2 has zero context from Agent 1. It can't rationalize failures it wasn't there to see. Independent verification is only real if it's structurally impossible to share context — not just requested.

And using BOSS to build BOSS closes the loop in a way that matters: the tool proved its own value by building itself.

---

### Results

- **88/88 requirements certified** by independent Agent 3
- **84 tests pass** (22 skip on Windows — bash-only functional tests)
- **CI green** on ubuntu-latest + macos-latest
- **0-to-shipped autonomously** — requirements in, green badge out
- Works on Python, Node, Go, Rust, Playwright
- Works on Linux, Mac, Windows (PowerShell 5.1), WSL

---

### The Vision

Every team using Claude Code should be able to say: *write the requirement, walk away, come back to a green badge.*

Not "AI helps with coding." AI does the coding. You do product and review. That's the actual leverage.

BOSS is the infrastructure that makes that real.

---

**GitHub:** https://github.com/geemboombaa/boss-claude-code

Install in one line:
```bash
curl -fsSL https://raw.githubusercontent.com/geemboombaa/boss-claude-code/master/install.sh | bash
```

---

*This post was written by me, about a project built autonomously by Claude Code, enforced by BOSS — which was also built autonomously by Claude Code. The recursion is intentional.*

---

---

## Full Implementation Deep Dive

---

### Project Genesis

The insight behind BOSS came from a specific failure mode: Claude Code confidently telling you tests pass while tests are red. This isn't a model capability issue. It's a structural gap — there's no mechanism that *blocks* Claude from responding when work is incomplete.

The question became: what's the minimum enforcement infrastructure that closes every gap between "Claude says done" and "actually done"?

The answer was 4 independent layers, each one failing independently of the others.

---

### Architecture Overview

```
User writes .boss/requirements.md
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│                     Claude Code Session                      │
│                                                              │
│  /build → spec.md + testplan.md                             │
│  /tdd → test-first implementation                           │
│  [writes code]                                              │
│         │                                                   │
│         ▼                                                   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Stop Hook (before every response)       │   │
│  │  if tests red → {"decision":"block","reason":"..."}  │   │
│  │  Claude receives failure, must fix before responding │   │
│  └─────────────────────────────────────────────────────┘   │
│         │                                                   │
│         ▼ (tests green)                                     │
│  ┌─────────────────────────────────────────────────────┐   │
│  │         PreToolUse Hooks (before every Write/Edit)   │   │
│  │  pre-build-gate: blocks until demo-signoff.md exists │   │
│  │  test-guard: blocks edits to baseline test files     │   │
│  └─────────────────────────────────────────────────────┘   │
│         │                                                   │
│         ▼ (gates clear)                                     │
│  /verify → Agent 2 (zero context) → verification.md        │
│  /certify → Agent 3 (zero context) → certification.json    │
│  git commit + push                                          │
└─────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│                    GitHub Actions CI                         │
│  ubuntu-latest + macos-latest matrix                        │
│  Runs independently — Claude has zero control               │
│  Posts BOSS certification status on every PR                │
└─────────────────────────────────────────────────────────────┘
```

---

### Layer 1: Stop Hook

**The core mechanism.** Before every Claude response, `stop-gate.sh` (Linux/Mac) or `stop-gate.ps1` (Windows) runs.

Input: JSON payload from Claude Code via stdin
```json
{
  "cwd": "/path/to/project",
  "stop_hook_active": false,
  "session_id": "abc123"
}
```

Output (on failure): JSON to stdout + exit 0
```json
{"decision": "block", "reason": "pytest failed: 3 tests failed\n...output..."}
```

**Flow:**
1. Parse cwd from payload (never use $PWD — hooks run from wrong directory)
2. Check `stop_hook_active` — if true, exit 0 immediately (prevents infinite loop)
3. Check `BOSS_SKIP=1` — emergency bypass
4. Check `BOSS_SKIP_PATTERNS` — if all changed files match patterns (e.g., `*.md,*.txt`), skip
5. Detect project type: pyproject.toml → pytest | package.json → npm test | go.mod → go test | Cargo.toml → cargo test
6. Find correct Python: `.venv/bin/python` → `venv/bin/python` → `env/bin/python` → system python3
7. Run test suite with `BOSS_RETRY` loop (retry N times on failure before blocking)
8. Capture stdout + stderr to `.boss/test-results/stdout.txt`
9. On failure: check `BOSS_WEBHOOK_URL`, POST JSON payload (for ntfy.sh/Slack/Discord notifications)
10. On failure: write block JSON to stdout

**Key constraint:** bash 3.2+ compatible (macOS ships bash 3.2). No bash 4+ features (associative arrays, `mapfile`, `read -d`). PowerShell 5.1 compatible (Windows default). No PS7+ syntax.

**Phase 2 additions to stop hook:**

```bash
# BOSS_SKIP_PATTERNS: skip gate when all changed files match patterns
if [ -n "${BOSS_SKIP_PATTERNS:-}" ] && command -v git >/dev/null 2>&1; then
    _CHANGED=$(git -C "$CWD" diff --name-only HEAD 2>/dev/null || echo "")
    _ALL_MATCH="true"
    while IFS= read -r _FILE; do
        [ -z "$_FILE" ] && continue
        _FILE_MATCHED="false"
        IFS=',' read -ra _PATS <<< "$BOSS_SKIP_PATTERNS"
        for _PAT in "${_PATS[@]}"; do
            case "$_FILE" in $_PAT) _FILE_MATCHED="true"; break;; esac
        done
        [ "$_FILE_MATCHED" = "false" ] && _ALL_MATCH="false" && break
    done <<< "$_CHANGED"
    if [ "$_ALL_MATCH" = "true" ] && [ -n "$_CHANGED" ]; then
        exit 0  # all changes match patterns, skip gate
    fi
fi

# BOSS_RETRY: retry N times before blocking
BOSS_RETRY="${BOSS_RETRY:-0}"
_ATTEMPT=0
while true; do
    # ... run tests ...
    [ $EXIT_CODE -eq 0 ] && break
    [ "$_ATTEMPT" -ge "$BOSS_RETRY" ] && break
    _ATTEMPT=$((_ATTEMPT + 1))
    sleep 2
done

# BOSS_WEBHOOK_URL: POST to webhook on block
if [ -n "${BOSS_WEBHOOK_URL:-}" ] && command -v curl >/dev/null 2>&1; then
    curl -s -X POST "$BOSS_WEBHOOK_URL" \
        -H 'Content-Type: application/json' \
        --data-binary "$WEBHOOK_PAYLOAD" \
        --max-time 5 >/dev/null 2>&1 || true
fi
```

---

### Layer 2: CEO Workflow

The process layer. Defined in CLAUDE.md templates installed into every project.

**Protocol:**
- Session start: read CLAUDE.md, run git log, run tests, check open issues
- New feature: use `/build` skill first — spec.md + testplan.md before any code
- TDD: tests written before implementation, red first
- Self-check before every "done" claim
- Never report success until tests pass locally

The "CEO walkaway" mode is the target state: user writes one requirement, Claude does everything, user reviews green CI. No managing in between.

This was validated by building BOSS itself: "CEO walkaway mode. Come to me only for unclear requirements, blockers, business changes, and signoff." Result: 88 requirements implemented autonomously.

---

### Layer 3: 3-Agent Verification Pipeline

**The insight:** AI self-review doesn't work. Claude reviewing its own code will rationalize failures. The solution is information isolation — not "ask Claude to be objective" but structurally prevent shared context.

**Agent 1 (Builder)**
- Has: full conversation context, requirements.md
- Writes: `.boss/spec.md`, `.boss/testplan.md`, all code, all tests
- Produces: committed code

**Agent 2 (Verifier)**
- Has: spec.md, git diff, test commands — nothing else
- Receives: zero context from Agent 1's conversation
- Runs: all tests independently
- Writes: `.boss/verification.md` with expected vs actual per requirement
- Captures: stdout, stderr, exit codes, screenshots if UI

**Agent 3 (Certifier)**
- Has: spec.md, verification.md — nothing else
- Receives: zero context from Agents 1 or 2
- Reads: raw artifacts (not prose summaries)
- Writes: `.boss/certification.json`

**certification.json schema:**
```json
{
  "certified": true,
  "requirements_passed": 88,
  "requirements_total": 88,
  "requirements_failed": 0,
  "coverage_pct": 94.2,
  "gaps": [],
  "certifier": "Agent 3 / Certifier",
  "timestamp": "2026-05-05T00:00:00Z"
}
```

The schema enforces: if `certified: true` then `gaps` must be empty array. If `gaps` is non-empty, `certified` must be false.

---

### Layer 4: GitHub Actions CI

Server-side gate. Claude has zero control — it can't modify CI while CI is running.

**Matrix:** ubuntu-latest + macos-latest on all 5 language templates + BOSS's own CI.

**PR comment job** (Phase 2 addition):
```yaml
comment-pr:
  runs-on: ubuntu-latest
  needs: test
  if: github.event_name == 'pull_request' && always()
  steps:
    - uses: actions/checkout@v4
    - name: Comment BOSS certification on PR
      continue-on-error: true
      env:
        GH_TOKEN: ${{ github.token }}
        BOSS_PR_NUMBER: ${{ github.event.pull_request.number }}
      run: |
        [ -f .boss/certification.json ] || exit 0
        python3 -c "import json,subprocess,os; \
          cert=json.load(open('.boss/certification.json')); \
          ok=cert.get('certified',False); \
          p=str(cert.get('requirements_passed','?')); \
          t=str(cert.get('requirements_total','?')); \
          mark='certified' if ok else 'NOT certified'; \
          msg='**BOSS '+mark+'** ('+p+'/'+t+' requirements)'; \
          cov=cert.get('coverage_pct'); \
          msg=(msg+' | coverage: '+str(int(cov))+'%') if cov is not None else msg; \
          pr=os.environ.get('BOSS_PR_NUMBER',''); \
          subprocess.run(['gh','pr','comment',pr,'--body',msg],capture_output=True) if pr else None" \
          2>/dev/null || true
```

Every PR gets a comment like:
```
**BOSS certified** (88/88 requirements) | coverage: 94%
```

or

```
**BOSS NOT certified** (85/88 requirements)
```

---

### Layer 5: Demo/Signoff Gate (PreToolUse)

Before any source file can be written or edited, `.boss/demo-signoff.md` must exist.

**Flow:**
1. User invokes `/demo` skill → Claude generates demo artifacts (wireframe.md, contract.md, or sequence.md based on project type)
2. User reviews artifacts — says "agreed" / "signoff"
3. `/signoff` skill writes `.boss/demo-signoff.md` with timestamp + approval text
4. `pre-build-gate.sh/.ps1` PreToolUse hook allows writes

This prevents Claude from diving into implementation before CEO has approved the design direction. It's the "show me before you build it" gate.

---

### Layer 6: Test Mutation Protection (Phase 2)

The `test-guard` PreToolUse hook protects test integrity.

**Problem:** Claude might rewrite tests to match broken implementation — making tests pass by weakening them.

**Solution:** Lazy baseline init on first PreToolUse per session:
1. On first `Write`/`Edit`/`MultiEdit` in a session, scan project for test files: `tests/`, `test/`, `__tests__/`, `spec/`, `test_*.py`, `*_test.py`, `*.test.ts`, etc.
2. Write list to `.boss/baseline-tests.txt`
3. Write session ID to `.boss/.baseline_session`
4. On subsequent tool calls: check if file_path is in baseline
5. If yes → block with `{"decision": "block", "reason": "Editing baseline test files is not permitted..."}`

```bash
# test-guard.sh - PreToolUse hook
TOOL_NAME=$(echo "$PAYLOAD" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tool_name',''))")
FILE_PATH=$(echo "$PAYLOAD" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))")

# Only gate Write/Edit/MultiEdit/NotebookEdit
case "$TOOL_NAME" in Write|Edit|MultiEdit|NotebookEdit) ;; *) exit 0;; esac

# BOSS_SKIP bypass
[ "${BOSS_SKIP:-}" = "1" ] && exit 0

# Lazy baseline init (once per session)
if [ ! -f "$BASELINE" ] || [ "$(cat "$SESSION_LOCK" 2>/dev/null)" != "$SESSION_ID" ]; then
    find "$CWD" -type f \( -name "test_*.py" -o -name "*_test.py" \
        -o -path "*/tests/*" -o -path "*/test/*" -o -path "*/__tests__/*" \
        -o -name "*.test.ts" -o -name "*.test.js" \) 2>/dev/null > "$BASELINE"
    echo "$SESSION_ID" > "$SESSION_LOCK"
fi

# Block if file is in baseline
if grep -qF "$FILE_ABS" "$BASELINE" 2>/dev/null; then
    printf '{"decision":"block","reason":"Editing baseline test file not permitted: %s"}\n' "$FILE_PATH"
fi
```

---

### Layer 7: Smart Delta

`scripts/boss-delta.py` — avoids re-running everything when requirements change.

1. Gets HEAD version of requirements.md via `git show HEAD:.boss/requirements.md`
2. Parses REQ-IDs from both versions
3. Identifies: new requirements, modified requirements, unchanged
4. Maps REQ-IDs to layers/phases
5. Outputs `.boss/run-plan.md`:
   - `FULL RUN` — no prior commit, or >50% requirements changed
   - `NO CHANGES` — requirements identical to HEAD
   - `PARTIAL RUN` — lists specific phases that need re-run

The `/build` skill checks for `run-plan.md` and skips unchanged phases. This matters on large projects — don't re-verify 70 requirements when 3 changed.

---

### Layer 8: CI-First Bootstrap

Before any source code exists, CI must be green.

The `/build` skill sequence:
1. Create GitHub repo
2. Push `.github/workflows/test.yml` + `.boss/spec.md` + `.boss/testplan.md`
3. Wait for CI green on bootstrap commit
4. Only then begin implementation

This ensures CI is never broken-by-default. The first state of CI is green (empty test run passes). Every subsequent commit must maintain that.

---

### Layer 9: BOSS_COVERAGE

`BOSS_COVERAGE=1` opt-in adds coverage tracking:

```bash
if [ -n "${BOSS_COVERAGE:-}" ] && [ "$BOSS_COVERAGE" = "1" ]; then
    if python3 -c "import pytest_cov" 2>/dev/null; then
        COV_ARGS="--cov --cov-report=term-missing:skip-covered"
    fi
fi
TEST_CMD="python3 -m pytest -q --tb=short --no-header --maxfail=5 $COV_ARGS"
```

Coverage percentage is parsed from test output and written to `certification.json` as `coverage_pct`. The certifier skill extracts it from stdout.txt.

---

### Installation

**Linux/Mac — one line:**
```bash
curl -fsSL https://raw.githubusercontent.com/geemboombaa/boss-claude-code/master/install.sh | bash
```

What it does:
1. Creates `~/.claude/boss/hooks/`
2. Copies `stop-gate.sh`, `pre-build-gate.sh`, `test-guard.sh` with `chmod +x`
3. Installs skills to `~/.claude/skills/<name>/SKILL.md` (auto-discovered by Claude Code)
4. Patches `~/.claude/settings.json` (idempotent — never overwrites existing hooks)
5. Detects project type, suggests matching CLAUDE.md template
6. Auto-installs pytest if not found (via uv or pip)
7. Checks node/go/cargo availability, warns if missing

**Windows — one line:**
```powershell
iwr https://raw.githubusercontent.com/geemboombaa/boss-claude-code/master/install.ps1 | iex
```

Additional Windows handling:
- WSL detection: checks `$env:WSL_DISTRO_NAME` + `$env:WSLENV`
- If WSL: writes bash hook commands (not PS1)
- If native: detects pwsh vs explicit `$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe`
- ASCII-safe strings throughout (no smart quotes, em-dashes)
- PS5.1 compatible (no ternary `?:`, no null-conditional `?.`)

---

### Test Suite

106 tests collected across 3 files:
- `tests/test_boss.py` — Layers 1-11 (core functionality)
- `tests/test_new_features.py` — Phase 1 additions (smart delta, CI matrix, demo/signoff)
- `tests/test_phase2.py` — Phase 2, Layers 12-16

84 pass on Windows (22 skipped — bash functional tests, skip on IS_WINDOWS).
All 106 pass on Linux/Mac.

---

### The Recursion

BOSS was built using BOSS.

Phase 1: used the stop hook (manually configured) + the 3-agent pipeline to build and verify all 11 layers.

Phase 2: CEO walkaway mode. User wrote requirements through REQ-088, said "agreed" at signoff. Claude implemented all 13 new requirements, ran 3-agent verification, committed, pushed. No other user interaction.

Result: `"certified": true, "requirements_passed": 88, "requirements_total": 88`.

The tool that enforces quality standards was itself built to those quality standards, enforced by itself.

---

### What's Next

- `npx @boss-claude/install` packaging
- Slack/Discord integration templates for `BOSS_WEBHOOK_URL`
- `/boss-status` skill: real-time dashboard of what phase each requirement is in
- Multi-agent parallel builds for large requirement sets
- BOSS_TIMEOUT per-requirement setting (some tests are slow)

---

**GitHub:** https://github.com/geemboombaa/boss-claude-code

```bash
curl -fsSL https://raw.githubusercontent.com/geemboombaa/boss-claude-code/master/install.sh | bash
```
