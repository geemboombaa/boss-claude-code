# BOSS Spec — For Agent 2 (Verifier) and Agent 3 (Certifier)

This is the specification that Agent 2 must verify and Agent 3 must certify against.
Source: .boss/requirements.md (condensed to testable assertions)

## Project
BOSS — Claude Code Enforcement Stack v1.0.0

## What Was Built
- `hooks/stop-gate.sh` — Stop hook for Linux/Mac
- `hooks/stop-gate.ps1` — Stop hook for Windows PowerShell 5.1
- `hooks/commit-msg.sh` — Conventional commits enforcement
- `hooks/pre-push.sh` — Pre-push test gate
- `scripts/patch-settings.py` — settings.json patcher
- `install.sh` — Linux/Mac installer
- `install.ps1` — Windows installer
- `bin/boss.js` + `package.json` — npx installer
- `skills/verify/SKILL.md` — Agent 2 verification skill
- `skills/certify/SKILL.md` — Agent 3 certification skill
- `templates/` — 6 CLAUDE.md templates
- `ci-templates/` — 5 GitHub Actions CI templates
- `.boss/schemas/certification.schema.json` — certification schema
- `tests/` — Python test suite

## Testable Assertions (verify each)

### SPEC-001: patch-settings.py creates settings.json when missing
Run: `python scripts/patch-settings.py --settings /tmp/test_settings.json --platform unix`
Expected: file created, contains Stop and SubagentStop hooks

### SPEC-002: patch-settings.py is idempotent
Run twice. Expected: no duplicate entries in Stop or SubagentStop arrays.

### SPEC-003: patch-settings.py preserves existing hooks
Create settings.json with existing hook. Run patcher. Expected: existing hook still present.

### SPEC-004: patch-settings.py creates timestamped backup
Run on existing file. Expected: settings.YYYYMMDDTHHMMSSZ.bak file created.

### SPEC-005: patch-settings.py handles malformed JSON gracefully
Write invalid JSON. Run. Expected: exit code 1, original file unchanged.

### SPEC-006: patch-settings.py dry-run makes no changes
Run with --dry-run. Expected: original file unchanged.

### SPEC-007: certification.schema.json is valid JSON Schema
File at .boss/schemas/certification.schema.json parses as valid JSON.

### SPEC-008: certification schema rejects certified:true with gaps
A certification with certified:true and non-empty gaps must fail schema validation.

### SPEC-009: All test files exist
tests/test_patch_settings.py, tests/test_certification_schema.py, tests/test_stop_gate_logic.py must exist.

### SPEC-010: Tests pass
Run: `python -m pytest tests/ -q`
Expected: all tests pass (or skip with documented reason)

### SPEC-011: stop-gate.sh exists and has executable bit in git index (mode 100755)
Run: `git ls-files --stage hooks/stop-gate.sh`
Expected: mode 100755 (not 100644)

### SPEC-012: stop-gate.ps1 exists and has valid PowerShell syntax
File exists at hooks/stop-gate.ps1. PowerShell syntax check passes.

### SPEC-013: BOSS_SKIP=1 bypass is handled
stop-gate.sh/ps1 checks BOSS_SKIP env var and exits 0 with log message.

### SPEC-014: stop_hook_active prevents infinite loop
Hook checks payload.stop_hook_active and exits 0 immediately if true.

### SPEC-015: Hook output is JSON {decision, reason} to stdout on failure
On test failure, hook writes valid JSON to stdout, not to stderr.

### SPEC-016: 6 CLAUDE.md templates exist
templates/python-backend.md, node-api.md, fullstack.md, go-service.md, rust-crate.md, generic.md all exist.

### SPEC-017: 5 CI templates exist
ci-templates/python.yml, node.yml, go.yml, rust.yml, playwright.yml all exist.

### SPEC-018: install.sh is valid bash (bash -n check)
Run: `bash -n install.sh`
Expected: no syntax errors.

### SPEC-019: package.json is valid JSON
package.json parses as valid JSON with name, version, bin fields present.

### SPEC-020: MIT LICENSE file exists
LICENSE file exists and contains "MIT License".

### SPEC-021: pre-build-gate.sh exists and is executable (100755)
File at hooks/pre-build-gate.sh with mode 100755 in git index.

### SPEC-022: pre-build-gate.ps1 exists with valid PowerShell-compatible structure
File at hooks/pre-build-gate.ps1. Contains decision/block JSON output logic.

### SPEC-023: pre-build-gate checks spec.md and demo-signoff.md
Both hooks gate on .boss/spec.md existence and .boss/demo-signoff.md absence.

### SPEC-024: pre-build-gate allows writes inside .boss/
Writes to .boss/ directory bypass the gate even when active.

### SPEC-025: pre-build-gate.sh blocks source writes, allows after signoff
When spec.md present + no signoff.md → block. When signoff.md present → allow.
Run: feed bash hook with payload; check stdout JSON decision field.

### SPEC-026: patch-settings.py registers PreToolUse hook
Run: python scripts/patch-settings.py --settings /tmp/test.json --platform unix
Expected: hooks.PreToolUse contains pre-build-gate entry with Write|Edit matcher.

### SPEC-027: boss-delta.py outputs run-plan.md
Run: python scripts/boss-delta.py --requirements .boss/requirements.md --output /tmp/run-plan.md
Expected: /tmp/run-plan.md created, contains FULL RUN or NO CHANGES or PARTIAL RUN.

### SPEC-028: All CI templates include ubuntu-latest + macos-latest matrix
Files: .github/workflows/test.yml, ci-templates/python.yml, node.yml, go.yml, rust.yml, playwright.yml
Expected: each has strategy.matrix.os containing both ubuntu-latest and macos-latest.

### SPEC-029: demo and signoff skills exist
skills/demo/SKILL.md and skills/signoff/SKILL.md both exist with relevant content.

### SPEC-030: All tests pass
Run: python -m pytest tests/ -q
Expected: 48+ pass, remaining skipped (bash-only on Windows).
