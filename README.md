# BOSS — Claude Code Enforcement Stack

[![BOSS CI](https://github.com/geemboombaa/boss-claude-code/actions/workflows/test.yml/badge.svg)](https://github.com/geemboombaa/boss-claude-code/actions/workflows/test.yml)

> Write the requirement. Walk away. Come back to a green CI badge.

---

## The Problem

AI coding agents have no enforcement layer. Claude Code will say "tests pass" and end its response while tests are red. Not maliciously — structurally. Nothing stops it.

The result: you become QA for your own AI assistant.

## The Fix: 4 Layers

**Layer 1 — Stop hook (local)**
Runs before every Claude response. If tests fail → Claude gets the error and must fix it. You only see responses where tests are green.

**Layer 2 — CEO workflow (process)**
Defined division of labor. You write requirements and review CI. Claude does research → TDD → implement → commit. No managing in between.

**Layer 3 — 3-agent verification**
Every completed feature goes through three independent agents:
- Agent 1 (Builder): writes spec + code + tests
- Agent 2 (Verifier): zero context, runs tests independently, documents proof
- Agent 3 (Certifier): zero context, certifies Agent 2's evidence against spec

Work is not done until `certification.json` says `"certified": true`.

**Layer 4 — CI (server-side)**
GitHub Actions runs on every push. Claude has zero control. Green badge = independently verified.

---

## Install

**Linux/Mac:**
```bash
curl -fsSL https://raw.githubusercontent.com/geemboombaa/boss-claude-code/master/install.sh | bash
```

**Windows:**
```powershell
iwr https://raw.githubusercontent.com/geemboombaa/boss-claude-code/master/install.ps1 | iex
```

**npm/npx:** _(coming soon — package not yet published)_

---

## What Gets Installed

| Component | What it does |
|---|---|
| Stop hook | Blocks Claude response when tests fail |
| SubagentStop hook | Blocks subagents too (separate registration) |
| CLAUDE.md template | CEO workflow, TDD rules, session protocol |
| /build skill | Agent 1 — spec + testplan before any code |
| /verify skill | Agent 2 — independent verification (zero context) |
| /certify skill | Agent 3 — independent certification (zero context) |
| GitHub Actions CI | Server-side gate Claude cannot influence |

---

## The CEO Workflow

```
You:    "Add rate limiting. 1 req/4h per IP. 429 + retry-after."
Claude: reads spec → /build → /tdd → implement → stop hook blocks on red →
        fix → green → /verify (Agent 2) → /certify (Agent 3) → commit → push
You:    open GitHub → green CI badge → review diff → merge
```

You write requirements. You review results. Claude does everything in between.

---

## Supported Languages

| Language | Test runner | Detection |
|---|---|---|
| Python | pytest (via uv or venv) | pyproject.toml, setup.py, pytest.ini |
| Node.js | npm test | package.json |
| Go | go test | go.mod |
| Rust | cargo test | Cargo.toml |
| Playwright | playwright test | playwright.config.* |

---

## 3-Agent Verification Model

```
Agent 1 (Builder)              Agent 2 (Verifier)           Agent 3 (Certifier)
─────────────────              ──────────────────           ───────────────────
Has: full context              Has: spec.md only            Has: spec.md +
                               + git diff                         verification.md
Writes:                        + test commands              only
  .boss/spec.md                                             
  .boss/testplan.md            Runs: tests                  Reads: raw artifacts
  all code                     independently                (not Agent 2 prose)
  all tests                    
                               Writes:                      Writes:
                               .boss/verification.md        .boss/certification.json
                                                            
                                                            certified: true|false
```

Information isolation is structural — not enforced by trust, but by what each agent receives.

---

## Escape Hatch

If the hook is blocking incorrectly:

```bash
BOSS_SKIP=1 claude
```

Always logged. Use sparingly.

---

## Emergency: Hook Not Running

Claude 4.7+ has a known regression where Stop hooks can be silently ignored. If you observe Claude responding while tests are red:
1. Verify hook is registered: `cat ~/.claude/settings.json | grep stop-gate`
2. Check Claude Code version: `claude --version`
3. CI is your fallback — it runs independently of the hook

---

## vs Other Tools

| Tool | What it does | vs BOSS |
|---|---|---|
| gstack | 23 advisory role personas | Advisory only — no enforcement gate |
| TDD Guard | Blocks premature implementation | Different gate — use both together |
| Everything Claude Code | 182+ skills catalog | Complex, no enforcement layer |

TDD Guard + BOSS = complementary. TDD Guard: test-first. BOSS: test-passing.

---

## Project Structure

```
boss/
├── hooks/
│   ├── stop-gate.sh       # Linux/Mac Stop hook
│   ├── stop-gate.ps1      # Windows Stop hook
│   ├── commit-msg.sh      # Conventional commits enforcement
│   └── pre-push.sh        # Pre-push test gate
├── skills/
│   ├── build/SKILL.md     # Agent 1 — builder protocol
│   ├── verify/SKILL.md    # Agent 2 — verifier
│   └── certify/SKILL.md   # Agent 3 — certifier
├── templates/             # CLAUDE.md templates (6 languages)
├── ci-templates/          # GitHub Actions (5 languages)
├── scripts/
│   └── patch-settings.py  # Idempotent settings.json patcher
├── install.sh             # Linux/Mac installer
├── install.ps1            # Windows installer
└── bin/boss.js            # npx entry point
```

---

## License

MIT
