# BOSS Requirements
_Version 1.0 — 2026-05-05_
_Source: BOSS.md + user requirements + live research_

---

## Users

| User | Context | Pain |
|---|---|---|
| Solo dev | Python/Node project, uses Claude Code daily | Claude lies about test results |
| Team lead | Multiple devs using Claude Code | No visibility into what Claude actually verified |
| CTO (lean team) | Wants AI to do work, not manage AI | Spends time as Claude's QA department |
| Windows dev | PowerShell 5.1 | Shell scripts written for bash don't work |
| Monorepo dev | Multiple languages in one repo | Test detection fails or runs wrong suite |
| New project (no tests) | Starting fresh | Hook should not block forever on empty test suite |

---

## Functional Requirements

### Layer 1: Stop Hook

| ID | Requirement | Testable? |
|---|---|---|
| REQ-001 | Stop hook blocks Claude response when test suite exits non-zero | Yes — break test, observe block |
| REQ-002 | Stop hook allows Claude response when test suite exits zero | Yes — all green, response proceeds |
| REQ-003 | Stop hook reads `cwd` from JSON payload (not $PWD) | Yes — run from different dir |
| REQ-004 | Stop hook checks `stop_hook_active` in payload, exits 0 immediately if true | Yes — prevents infinite loop |
| REQ-005 | Stop hook outputs `{"decision":"block","reason":"..."}` to stdout + exits 0 (no exit code 2) | Yes — parse stdout |
| REQ-006 | Stop hook writes human-readable failure output to stderr | Yes — observe stderr |
| REQ-007 | Stop hook skips if `BOSS_SKIP=1` env var is set (emergency bypass) | Yes — set var, observe skip |
| REQ-008 | Stop hook skips gracefully when no test files found, logs reason | Yes — empty project |
| REQ-009 | Stop hook times out after 10 minutes, fails open (exit 0) with warning | Yes — simulate slow suite |
| REQ-010 | Stop hook works on Linux/Mac (bash 3.2+) | Yes — run on Linux/Mac |
| REQ-011 | Stop hook works on Windows PowerShell 5.1, all strings ASCII-safe | Yes — run on Windows |
| REQ-012 | SubagentStop hook registered separately (subagents bypass main Stop hook) | Yes — verify subagent blocked |
| REQ-013 | Python: finds venv at .venv, venv, env — falls back to system python | Yes — test each path |
| REQ-014 | Python: runs `pytest -q --tb=short --no-header --maxfail=5` | Yes — check command |
| REQ-015 | Node: runs `npm test --if-present` | Yes — check command |
| REQ-016 | Go: runs `go test ./...` | Yes — check command |
| REQ-017 | Rust: runs `cargo test --quiet` | Yes — check command |
| REQ-018 | If hook itself crashes: fails open (exit 0), logs error | Yes — corrupt hook, observe |

### Layer 2: Install

| ID | Requirement | Testable? |
|---|---|---|
| REQ-019 | `curl -fsSL .../install.sh \| bash` installs on Linux/Mac | Yes — Docker clean env |
| REQ-020 | PowerShell install script installs on Windows | Yes — clean PS session |
| REQ-021 | `npx @boss-claude/install` installs on any OS with Node | Yes — npx run |
| REQ-022 | Creates `~/.claude/boss/hooks/` directory | Yes — check after install |
| REQ-023 | Patches `~/.claude/settings.json` — merges Stop + SubagentStop hooks, never overwrites | Yes — check before/after |
| REQ-024 | Install is idempotent — running twice produces identical state | Yes — run twice, diff result |
| REQ-025 | Backs up settings.json to settings.json.bak before patching | Yes — check backup exists |
| REQ-026 | Detects project type, suggests matching CLAUDE.md template | Yes — observe prompt |
| REQ-027 | Asks before overwriting existing CLAUDE.md | Yes — run on project with CLAUDE.md |
| REQ-028 | Optionally copies `.github/workflows/test.yml` CI template | Yes — check file created |
| REQ-029 | Prints every action taken — no silent changes | Yes — read output |
| REQ-030 | `--quiet` flag suppresses interactive prompts for CI/scripted use | Yes — run with flag |
| REQ-031 | Checks Claude Code installed, errors with instructions if not | Yes — hide claude binary |
| REQ-032 | Handles missing settings.json (creates it) | Yes — delete settings.json |
| REQ-033 | Handles malformed settings.json (errors gracefully, does not corrupt) | Yes — write invalid JSON |

### Layer 3: 3-Agent Verification Pipeline

| ID | Requirement | Testable? |
|---|---|---|
| REQ-034 | Agent 1 (Builder) writes `.boss/spec.md` before coding | Yes — file exists after build |
| REQ-035 | Agent 1 writes `.boss/testplan.md` before coding | Yes — file exists after build |
| REQ-036 | Agent 2 (Verifier) receives ZERO context from Agent 1 conversation | Yes — verify no shared memory |
| REQ-037 | Agent 2 reads only: `.boss/spec.md` + `git diff` + test commands | Yes — verify inputs |
| REQ-038 | Agent 2 runs all tests independently | Yes — observe test execution |
| REQ-039 | Agent 2 captures proof: stdout, stderr, exit codes, screenshots (if UI) | Yes — check artifacts |
| REQ-040 | Agent 2 writes `.boss/verification.md` with expected vs actual per requirement | Yes — file exists, has content |
| REQ-041 | Agent 3 (Certifier) receives ZERO context from Agents 1 or 2 | Yes — verify no shared memory |
| REQ-042 | Agent 3 reads only: `.boss/spec.md` + `.boss/verification.md` | Yes — verify inputs |
| REQ-043 | Agent 3 writes `.boss/certification.json` matching schema | Yes — validate against schema |
| REQ-044 | `certification.json` includes: certified, certifier_agent, timestamp, requirements_met, gaps, proof_artifacts | Yes — schema validation |
| REQ-045 | Work is NOT complete until certification.json exists with `certified: true` | Yes — gate enforced |

### Layer 4: CLAUDE.md Templates

| ID | Requirement | Testable? |
|---|---|---|
| REQ-046 | Every template includes session start protocol (read file, git log, run tests, check issues) | Yes — read template |
| REQ-047 | Every template includes hard rules section with /tdd, stop hook, self-check requirements | Yes — read template |
| REQ-048 | Every template has What Is / What Is Not / Tech Stack / Phase Plan / Where To Look sections | Yes — read template |
| REQ-049 | Templates exist for: python-backend, node-api, fullstack, go-service, rust-crate, generic | Yes — list files |
| REQ-050 | python-backend template uses uv + pytest + FastAPI conventions | Yes — read template |
| REQ-051 | fullstack template includes Playwright E2E instructions | Yes — read template |

### Layer 5: CI Templates

| ID | Requirement | Testable? |
|---|---|---|
| REQ-052 | CI templates exist for: python, node, go, rust, playwright | Yes — list files |
| REQ-053 | Python CI uses uv + pytest + junitxml artifact upload | Yes — read YAML |
| REQ-054 | Playwright CI is separate job with 30-min timeout + screenshot artifact | Yes — read YAML |
| REQ-055 | CI merge gate references certification.json (BOSS_AGENTS=true path) | Yes — read YAML |
| REQ-056 | CI runs on: ubuntu-latest, test matrix includes platform check | Yes — read YAML |

### Layer 6: Visual UI Testing

| ID | Requirement | Testable? |
|---|---|---|
| REQ-057 | Playwright `toHaveScreenshot()` integrated into fullstack template | Yes — template includes it |
| REQ-058 | Screenshots stored as CI artifacts per-run | Yes — read YAML |
| REQ-059 | Visual diff (pixelmatch) runs on screenshot comparison | Yes — test output shows diff |
| REQ-060 | Agent 2 captures screenshots as proof artifacts | Yes — .boss/ has screenshots |

### Layer 7: Git Discipline

| ID | Requirement | Testable? |
|---|---|---|
| REQ-061 | commit-msg hook enforces conventional commits format | Yes — bad commit rejected |
| REQ-062 | pre-push hook runs test suite before every push | Yes — break test, push blocked |

### Layer 8: CI-First Bootstrap

| ID | Requirement | Testable? |
|---|---|---|
| REQ-063 | /build skill creates GitHub repo + pushes CI workflow BEFORE any code committed | Yes — git log shows CI commit first |
| REQ-064 | CI must pass on bootstrap commit before code phase begins | Yes — gh run list shows green |
| REQ-065 | Bootstrap commit contains only .github/workflows/test.yml + .boss/spec.md + .boss/testplan.md | Yes — git show first commit |

### Layer 9: Smart Delta

| ID | Requirement | Testable? |
|---|---|---|
| REQ-066 | scripts/boss-delta.py diffs .boss/requirements.md against git HEAD version | Yes — modify req, run script |
| REQ-067 | boss-delta.py outputs .boss/run-plan.md listing changed REQ IDs and affected phases | Yes — read output file |
| REQ-068 | /build skill runs boss-delta.py when requirements.md is git-tracked; skips unchanged phases | Yes — no-change run skips phases |

### Layer 10: CI Matrix

| ID | Requirement | Testable? |
|---|---|---|
| REQ-069 | BOSS own CI and all 5 CI templates run on matrix: ubuntu-latest + macos-latest | Yes — workflow matrix key present |

### Layer 11: Demo/Signoff Gate

| ID | Requirement | Testable? |
|---|---|---|
| REQ-070 | Agent 1 generates .boss/demo-artifacts/ BEFORE writing any source code | Yes — dir exists before first src commit |
| REQ-071 | Demo artifacts: UI→wireframe.md, API→contract.md, service→sequence.md (project-type based) | Yes — file exists, has content |
| REQ-072 | PreToolUse hook blocks Write/Edit on non-.boss/ files until .boss/demo-signoff.md exists | Yes — attempt write, observe block |
| REQ-073 | /demo skill generates demo artifacts from .boss/spec.md | Yes — invoke /demo, check .boss/demo-artifacts/ |
| REQ-074 | /signoff skill records CEO approval to .boss/demo-signoff.md with timestamp | Yes — invoke /signoff, read file |
| REQ-075 | pre-build-gate hook registered as PreToolUse event in settings.json | Yes — grep settings.json |

---

## Non-Functional Requirements

| ID | Requirement |
|---|---|
| REQ-NFR-001 | Stop hook completes in <5s for typical suite (--maxfail=5 enforces this) |
| REQ-NFR-002 | No dependencies beyond bash/PS1 (jq optional, python3 fallback for JSON) |
| REQ-NFR-003 | bash 3.2+ compatible (macOS ships bash 3.2) |
| REQ-NFR-004 | PowerShell 5.1+ compatible (Windows default) |
| REQ-NFR-005 | All PS1 strings ASCII-safe (no em-dashes, smart quotes, non-Latin) |
| REQ-NFR-006 | Settings.json patch non-destructive (never removes existing entries) |
| REQ-NFR-007 | Idempotent install (no duplicates, no errors on second run) |
| REQ-NFR-008 | Every action logged/visible — no silent failures or successes |
| REQ-NFR-009 | BOSS_SKIP=1 provides emergency bypass documented prominently |
| REQ-NFR-010 | Hook crash = fail open (exit 0) — broken hook never permanently blocks |
| REQ-NFR-011 | Works in monorepo from subdirectory (uses cwd from payload) |
| REQ-NFR-012 | MIT license |
| REQ-NFR-013 | Zero cost to run (BOSS itself free; runs user's existing tests) |

---

## Out of Scope

- BOSS has no UI of its own
- No telemetry or analytics
- No IDE integration beyond Claude Code
- Does not replace TDD Guard (complements it)
- Does not store secrets or credentials
- Does not manage Claude API keys
- Does not support non-Claude AI coding agents

---

## Definition of Done

A requirement is DONE when:
1. Code implementing it exists in git
2. Test for it exists in git
3. Test passes (verified in CI)
4. Agent 2 ran it independently and documented in `.boss/verification.md`
5. Agent 3 certified it in `.boss/certification.json`

Self-reporting "done" without these 5 conditions = not done.
