# BOSS Research Report — Live Web Search (2026-05-05)

## Existing Tools

| Project | Stars | What It Does | Gap vs BOSS |
|---|---|---|---|
| everything-claude-code (affaan-m) | 140k+ | 48 agents, 182 skills, AgentShield security 3-agent pipeline | No universal test enforcement, no CEO workflow |
| gstack (garrytan) | 89.8k | 23 advisory personas, sprint workflow | No Stop hook, no CI templates, pure advisory |
| awesome-claude-code (hesreallyhim) | 36.8k | Curated list — skills, hooks, commands | Curation only |
| rohitg00/awesome-claude-code-toolkit | ~5k | 135 agents, 176+ plugins, 20 hooks | Not unified, no install script |
| alinaqi/claude-bootstrap | unknown | CLAUDE.md + @include, Stop hook TDD loop, pre-push hooks, CI/CD | JS-centric, not universal |
| claude-code-hooks-mastery (disler) | low-mid hundreds | Python hook scripts, multi-agent patterns | No install, no CI templates, no CEO workflow |
| metaswarm (dsifry) | 149 | 18 agents, quality gates as blocking state transitions | Not installable, not universal |
| TDD Guard (nizos) | 2.1k | Blocks edits when TDD rules violated | No Stop hook for response blocking, no CI |
| davila7/claude-code-templates | unknown | CLI for configuring Claude Code, 100+ templates | Monitor/config only |

## Gap Confirmed
No single installable package combining:
- Stop hook (test enforcement, universal language detection)
- 3-agent verification pipeline (Builder → Verifier → Certifier)
- CEO walkaway workflow (CLAUDE.md templates with session protocol)
- CI templates (per language, merge-gated)
- Visual UI test verification (Playwright built-in)
- One-command install (curl / npx)

## Critical Hook Technical Findings

### Payload Format (Stop hook, confirmed current)
```json
{
  "session_id": "...",
  "transcript_path": "...",
  "cwd": "...",
  "hook_event_name": "Stop",
  "stop_hook_active": false
}
```
- `stop_hook_active` EXISTS — check at top of every Stop hook, exit 0 if true
- `cwd` EXISTS — always use this, never $PWD

### Exit Mechanism
- JSON `{"decision": "block", "reason": "..."}` to stdout + exit 0 = CORRECT
- Exit code 2 = legacy, mutually exclusive with JSON output
- If exit 2: JSON is silently ignored

### Known Active Bugs (May 2026)
- Claude 4.7 ignoring Stop hooks entirely (HN thread active)
- Prompt-based Stop hooks cannot read transcript (issue #11786)
- Subagents BYPASS main Stop hook — need separate SubagentStop hook
- Exit code 2 broken in plugin scope (issue #10412)

### BOSS Mitigation
- Use JSON + exit 0 (avoids exit-code bugs)
- Register SubagentStop hook in addition to Stop hook
- CI is the fallback — if local hook broken, CI blocks merge
- Document Claude 4.7 regression, pin to tested version in install instructions

## Visual Testing
- Playwright `toHaveScreenshot()` uses pixelmatch — zero dependencies
- Lost Pixel (MIT, 1.7k stars) for baseline management + PR diffs
- No external service needed for basic visual regression

## Install Script Patterns
- Use `set -euo pipefail`
- Use `mktemp` not fixed /tmp paths
- jq for JSON patching, python3 fallback
- curl: `-fsSL` flags
- Idempotency: `mkdir -p`, `ln -sf`, check before install

## Sources
- https://code.claude.com/docs/en/hooks
- https://claudefa.st/blog/tools/hooks/hooks-guide
- https://claudefa.st/blog/tools/hooks/stop-hook-task-enforcement
- https://github.com/anthropics/claude-code/issues/55334
- https://github.com/anthropics/claude-code/issues/11786
- https://news.ycombinator.com/item?id=47895029
- https://github.com/alinaqi/claude-bootstrap
- https://github.com/dsifry/metaswarm
- https://playwright.dev/docs/test-snapshots
- https://github.com/lost-pixel/lost-pixel
- https://arslan.io/2019/07/03/how-to-write-idempotent-bash-scripts/
