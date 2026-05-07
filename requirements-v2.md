# BOSS Requirements v2 — Complete Vision
_Source: fulllies.md — full session transcript_
_Date: 2026-05-06_

THIS REPLACES the partial requirements.md.
The v1 requirements captured enforcement mechanics only.
This captures the complete CEO walkaway vision.

---

## The Vision (exact words from CEO)

"CEO writes requirement, walks away, comes back to green CI badge."
"Run everything autonomously. Only stop if CEO input needed on design or business."
"3 agent: agent 1 creates all specs, test plans, code. agent 2 zero context, runs tests with proof.
 agent 3 zero context, certifies. then and only then complete."

---

## CARRIED FORWARD — Enforcement Mechanics (v1, REQ-001 to REQ-088)

All 88 requirements in requirements.md are still valid and still apply.
This document adds the MISSING walkaway layer.

---

## NEW — Walkaway Pipeline (REQ-W01 to REQ-W20)

### Auto-Push Layer

| ID | Requirement | Proof |
|---|---|---|
| REQ-W01 | PostToolUse hook fires after every Bash tool call that contains `git commit` | settings.json has PostToolUse entry matching Bash; test commits and verifies hook fires |
| REQ-W02 | Auto-push hook pushes to remote branch `boss/<req-slug>` after every commit | git remote shows branch created after commit |
| REQ-W03 | Branch slug derived from first line of CLAUDE.md requirement section, lowercased, spaces→hyphens | branch name matches requirement text |
| REQ-W04 | BOSS_BRANCH_PREFIX env var overrides default `boss/` prefix | set var, verify branch name |
| REQ-W05 | If remote branch does not exist, auto-push creates it with `-u origin` | fresh repo test: branch created |
| REQ-W06 | Auto-push is skipped if `BOSS_SKIP=1` | set var, commit, verify no push |
| REQ-W07 | Auto-push logs action to stderr (not silent) | observe stderr after commit |

### Auto-PR Layer

| ID | Requirement | Proof |
|---|---|---|
| REQ-W08 | After first push to new branch, auto-creates PR via `gh pr create` | PR exists on GitHub after push |
| REQ-W09 | PR title = first line of original requirement | read PR title on GitHub |
| REQ-W10 | PR body contains: requirement text, `.boss/spec.md` summary, CI badge link | read PR body |
| REQ-W11 | PR creation is idempotent — if PR already exists for branch, skip | run twice, one PR created |
| REQ-W12 | If `gh` CLI not installed or not authenticated, log warning and skip (do not crash) | remove gh, observe graceful skip |

### Notification Layer

| ID | Requirement | Proof |
|---|---|---|
| REQ-W13 | BOSS_NOTIFY env var: webhook URL POSTed when CI job completes (pass or fail) | set URL, push, verify POST received |
| REQ-W14 | Notification payload: `{event, repo, branch, pr_url, ci_status, test_summary}` | inspect POST body |
| REQ-W15 | If BOSS_NOTIFY not set, notification silently skipped | no env var, no error |

### Orchestration Layer — /run skill

| ID | Requirement | Proof |
|---|---|---|
| REQ-W16 | `/run` skill exists at `~/.claude/skills/run/SKILL.md` | file exists after install |
| REQ-W17 | `/run` executes full pipeline in order: research → spec → testplan → TDD → code → /verify → /certify → commit → push → PR | skill invocation produces all artifacts in order |
| REQ-W18 | `/run` is the single entry point — CEO types requirement, invokes `/run`, walks away | one command, no other input needed |
| REQ-W19 | `/run` stops and surfaces to CEO ONLY for: design changes, business decisions, external blockers | test: ambiguous requirement → /run asks one clarifying question, not multiple |
| REQ-W20 | `/run` resumes from last completed phase if interrupted (reads `.boss/run-plan.md`) | kill mid-run, restart, verify no double-work |

### CI Gate

| ID | Requirement | Proof |
|---|---|---|
| REQ-W21 | CI merge gate step checks `.boss/certification.json` exists with `certified: true` | push without certifying, PR blocked |
| REQ-W22 | All 5 CI templates updated with certification gate step | read each YAML |

### Missing from v1

| ID | Requirement | Proof |
|---|---|---|
| REQ-W23 | `hooks/pre-push.ps1` exists (Windows pre-push gate) | file exists |
| REQ-W24 | `.boss/schemas/spec.schema.json` exists and validates spec.md format | jsonschema validation passes |
| REQ-W25 | install.ps1 generates hook command without PS `&` call operator (cmd.exe compatible) | grep generated settings.json |
| REQ-W26 | install.sh + install.ps1 both installed as hooks in BOSS own .github/workflows | CI runs both |

---

## Definition of Done (unchanged)

A requirement is DONE when:
1. Code implementing it exists in git
2. Test for it exists in git — written BEFORE code (TDD)
3. Test passes in CI
4. Agent 2 ran it independently, documented in `.boss/verification.md`
5. Agent 3 certified it in `.boss/certification.json`

Self-reporting done without these 5 = NOT done.
