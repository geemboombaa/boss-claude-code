# Sequence Diagram: BOSS Enhancement Round 2
Date: 2026-05-06

## Layer 12 — Stop Hook Reliability

### BOSS_RETRY flow (REQ-076)
```
User sets BOSS_RETRY=2
Claude finishes response
  → stop-gate fires
  → tests fail on attempt 1
  → wait 2s, retry
  → tests fail on attempt 2
  → block (output JSON {decision:block})
```
vs without retry: block on attempt 1.

### BOSS_SKIP_PATTERNS flow (REQ-077)
```
User sets BOSS_SKIP_PATTERNS="*.md,*.txt"
Claude edits README.md
  → stop-gate fires
  → gate reads changed files from git (git diff --name-only HEAD)
  → ALL files match *.md pattern
  → exit 0 immediately (no test run)
```
If ANY file does NOT match → run tests normally.

### BOSS_WEBHOOK_URL flow (REQ-078)
```
User sets BOSS_WEBHOOK_URL=https://ntfy.sh/my-topic
Tests fail → stop-gate blocks
  → before outputting JSON, curl POST to BOSS_WEBHOOK_URL
  → payload: {"event":"block","project":"<cwd-basename>","summary":"<first 200 chars of failure>"}
  → curl has 5s timeout, failure is silently ignored (never blocks the block itself)
```

---

## Layer 13 — Test Mutation Protection

### test-guard flow (REQ-079, REQ-080)
```
Session start (PostToolUse on any first tool? No — separate mechanism):
  → A new PostToolUse hook: test-guard-baseline.sh
  → Runs once per session (lockfile .boss/.baseline_written_<session_id>)
  → Writes .boss/baseline-tests.txt: list of all files in tests/ at session start

On every Write/Edit (PreToolUse):
  → test-guard hook reads .boss/baseline-tests.txt
  → If target file_path is in baseline-tests.txt → BLOCK
  → Message: "Cannot edit pre-existing test files. Create new test files instead."
  → If .boss/baseline-tests.txt doesn't exist → allow (no baseline yet)
```

**Design decision made**: uses two hooks:
1. `test-guard-baseline.sh` (PostToolUse, fired once) — writes baseline
2. `test-guard.sh` (PreToolUse, Write|Edit matcher) — enforces it

Actually simpler: combine into one. test-guard.sh:
- On PreToolUse: if baseline-tests.txt missing, write it now (lazy init)
- Then check if target file is in baseline

---

## Layer 14 — Verification Model

### Agent 2 stdout (REQ-082)
Change in verify/SKILL.md: add line mandating Agent 2 reads .boss/test-results/stdout.txt
No code change — skill file update only.

### Coverage schema (REQ-083, REQ-084)
certification.schema.json: add optional property coverage_pct (number, 0-100).
certify/SKILL.md: instruct Agent 3 to extract coverage from stdout.txt if present.
stop-gate.sh/ps1: add --cov flag when BOSS_COVERAGE=1 env var set (optional opt-in).

---

## Layer 15 — GitHub Integrations

### PR comment step (REQ-085)
Each CI template gets a new job step after test:
```yaml
- name: Comment certification on PR
  if: github.event_name == 'pull_request' && always()
  env:
    GH_TOKEN: ${{ github.token }}
  run: |
    if [ -f .boss/certification.json ]; then
      CERT=$(python -c "import json; c=json.load(open('.boss/certification.json')); \
        print(f'BOSS: {\"certified\" if c[\"certified\"] else \"NOT certified\"} \
        ({c[\"requirements_passed\"]}/{c[\"requirements_total\"]})')")
      gh pr comment ${{ github.event.pull_request.number }} --body "$CERT" || true
    fi
```

### Badge (REQ-086)
README gets:
```
[![BOSS CI](https://github.com/geemboombaa/boss-claude-code/actions/workflows/test.yml/badge.svg)](https://github.com/geemboombaa/boss-claude-code/actions/workflows/test.yml)
```

---

## Layer 16 — Windows / WSL Hardening

### WSL detection (REQ-087, REQ-088)
install.ps1 currently writes:
```
powershell -ExecutionPolicy Bypass -File "~/.claude/boss/hooks/stop-gate.ps1"
```
Problem: if hook runs inside WSL, `powershell` may not resolve.

Fix: detect at install time whether running in WSL via `$env:WSL_DISTRO_NAME` or
`(Get-Process -Id $PID).MainModule.FileName` containing `wsl`.
Write explicit path:
- PS5.1: `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`
- PS7: path from `(Get-Command pwsh).Source`
- If WSL detected: write bash hook path instead (stop-gate.sh)

---

## What Does NOT Change
- 3-agent verification pipeline unchanged
- certification.json schema: backward compatible (new field optional)
- All existing tests must keep passing
- CI matrix (ubuntu + macos) unchanged
