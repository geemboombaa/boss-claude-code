# BOSS Architecture
_Version 1.0 — 2026-05-05_

---

## System Overview

```
User writes requirement
        |
        v
[Claude Code session starts]
        |
        v
[CLAUDE.md loaded — session protocol runs automatically]
        |
        v
[Agent 1 builds: spec -> testplan -> TDD -> code -> commit]
        |
        v
[Stop hook fires on every response attempt]
        |-- tests FAIL --> {"decision":"block"} --> Claude must fix
        |-- tests PASS --> response allowed
        |
        v
[/verify invoked — Agent 2 spawned cold]
        |
        v
[/certify invoked — Agent 3 spawned cold]
        |-- FAIL --> gaps listed, back to Agent 1
        |-- PASS --> .boss/certification.json written
        |
        v
[pre-push hook: tests run before git push]
        |
        v
[GitHub Actions CI: independent server-side verification]
        |-- red --> merge blocked
        |-- green --> merge allowed
```

---

## Components

### hooks/stop-gate.sh (Linux/Mac)
- **Trigger:** Claude Code Stop event
- **Input:** JSON on stdin `{session_id, cwd, stop_hook_active, ...}`
- **Logic:** check `stop_hook_active` → detect language → find venv → run tests → block or allow
- **Output:** `{"decision":"block","reason":"..."}` to stdout on fail; nothing on pass
- **Stderr:** human-readable status messages
- **Timeout:** 600s, fails open
- **Deps:** bash 3.2+, python3 (for JSON parsing), no jq required

### hooks/stop-gate.ps1 (Windows)
- Same logic as .sh, PowerShell 5.1
- ASCII-only strings (CP1252 encoding constraint)
- `[Console]::Error.WriteLine()` for stderr
- `Start-Process` with `WaitForExit(600000)` for timeout

### hooks/commit-msg.sh + commit-msg.ps1
- Enforces conventional commits: `type(scope): description`
- Types: feat|fix|docs|test|refactor|chore|ci
- Blocks commit if format invalid

### hooks/pre-push.sh + pre-push.ps1
- Runs full test suite before every push
- Blocks push if tests fail
- Same language detection as stop-gate

### scripts/patch-settings.py
- Called by install scripts to patch ~/.claude/settings.json
- Reads existing JSON (creates if missing)
- Validates JSON (errors gracefully on malformed)
- Merges Stop + SubagentStop hooks (idempotent)
- Backs up to settings.json.bak before writing
- Never removes existing entries

### skills/verify/SKILL.md (Agent 2 — Verifier)
- Spawned with ZERO context from Agent 1
- Inputs: `.boss/spec.md` + `git diff` + test commands only
- Runs tests independently
- Captures proof: stdout, exit codes, screenshots (Playwright if detected)
- Writes `.boss/verification.md`

### skills/certify/SKILL.md (Agent 3 — Certifier)
- Spawned with ZERO context from Agents 1 or 2
- Inputs: `.boss/spec.md` + `.boss/verification.md` only
- Compares expected vs actual per requirement ID
- Writes `.boss/certification.json`
- PASS requires ALL requirements met

### install.sh (Linux/Mac installer)
- curl-installable: `curl -fsSL .../install.sh | bash`
- Creates `~/.claude/boss/hooks/`
- Copies stop-gate.sh, commit-msg.sh, pre-push.sh
- Calls patch-settings.py
- Interactive: template selection + CI setup
- Flags: `--quiet`, `--skip-ci`, `--template=python`
- Idempotent, non-destructive

### install.ps1 (Windows installer)
- Same flow as install.sh, PowerShell 5.1

### package.json (npx installer)
- `npx @boss-claude/install` → runs install.sh or install.ps1 based on OS

### templates/*.md (CLAUDE.md templates)
- python-backend, node-api, fullstack, go-service, rust-crate, generic
- Each includes: What Is / What Is Not / Tech Stack / Phase Plan / Hard Rules / Session Protocol / Where To Look

### ci-templates/*.yml (GitHub Actions)
- python.yml, node.yml, go.yml, rust.yml, playwright.yml
- Each: checkout → setup → test → artifact upload
- BOSS_AGENTS=true path: adds Agent 2 + Agent 3 CI jobs (requires ANTHROPIC_API_KEY secret)

---

## Data Flow: .boss/ Directory

```
.boss/
├── spec.md              ← Agent 1 writes before coding
├── testplan.md          ← Agent 1 writes before coding
├── verification.md      ← Agent 2 writes after running tests
├── certification.json   ← Agent 3 writes after certifying
├── test-results/        ← test output artifacts
│   ├── junit.xml
│   ├── stdout.txt
│   └── screenshots/     ← Playwright captures (if UI)
├── research/            ← build-time research (this project)
├── schemas/
│   ├── certification.schema.json
│   └── spec.schema.json
└── .gate_running        ← lockfile (deleted after each hook run)
```

---

## Hook Payload (Stop event)

```json
{
  "session_id": "uuid",
  "transcript_path": "/path/.../session.jsonl",
  "cwd": "/path/to/project",
  "hook_event_name": "Stop",
  "stop_hook_active": false
}
```

**Critical:** `stop_hook_active=true` means we're already in a forced-continuation loop. Exit 0 immediately.

---

## settings.json Wire

```json
{
  "hooks": {
    "Stop": [{
      "matcher": "",
      "hooks": [{"type": "command", "command": "bash ~/.claude/boss/hooks/stop-gate.sh"}]
    }],
    "SubagentStop": [{
      "matcher": "",
      "hooks": [{"type": "command", "command": "bash ~/.claude/boss/hooks/stop-gate.sh"}]
    }]
  }
}
```
Windows: `powershell -File "~/.claude/boss/hooks/stop-gate.ps1"`

---

## 3-Agent Information Boundaries

```
Agent 1 (Builder)
  CAN SEE: full conversation, CLAUDE.md, codebase
  WRITES:  .boss/spec.md, .boss/testplan.md, all code, all tests

Agent 2 (Verifier) — COLD START
  CAN SEE: .boss/spec.md, git diff output, test command list
  CANNOT SEE: Agent 1 conversation, reasoning, code files (reads via diff only)
  WRITES:  .boss/verification.md

Agent 3 (Certifier) — COLD START
  CAN SEE: .boss/spec.md, .boss/verification.md
  CANNOT SEE: Agent 1 or 2 conversations, codebase, test output directly
  WRITES:  .boss/certification.json
```

---

## Key Technical Decisions

| Decision | Choice | Reason |
|---|---|---|
| Hook output format | JSON + exit 0 (not exit code 2) | exit 2 and JSON are mutually exclusive |
| Loop prevention | stop_hook_active flag + lockfile | belt and suspenders |
| JSON parsing in bash | python3 (no jq dep) | universal, no install needed |
| Venv detection | .venv > venv > env > system | most common first |
| CI agents default | Option C: isolated jobs default, API agents opt-in | free by default |
| Visual testing | Playwright built-in toHaveScreenshot | zero deps, pixelmatch bundled |
| Install backup | settings.json.bak always | non-destructive guarantee |
| Timeout behavior | fail open (exit 0) | broken hook never permanently blocks |
| SubagentStop | registered separately from Stop | subagents bypass main Stop hook |

---

## Risk Register

| Risk | Mitigation |
|---|---|
| Claude 4.7 ignoring Stop hooks (active bug) | CI is fallback; document; pin version |
| Prompt-based hooks broken | Command-based only (shell scripts) |
| Subagents bypass Stop | Register SubagentStop hook |
| exit code 2 + JSON conflict | JSON + exit 0 only |
| PS1 CP1252 encoding crash | ASCII-only strings in all PS1 files |
| settings.json corruption | Backup + validate before write |
| Infinite hook loop | stop_hook_active check + lockfile |
