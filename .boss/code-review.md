# BOSS Code Review
Reviewer: independent agent (zero prior context)
Date: 2026-05-05
Scope: stop-gate.sh, stop-gate.ps1, patch-settings.py, install.sh, install.ps1, skills/verify/SKILL.md, skills/certify/SKILL.md
Reference: .boss/requirements.md v1.0

---

## Security Vulnerabilities

---

- File: hooks/stop-gate.sh
- Severity: HIGH
- Line: 73
- Problem: Race condition in lockfile creation. The check `if [ -f "$LOCK_FILE" ]` and the subsequent `echo $$ > "$LOCK_FILE"` are not atomic. Two concurrent gate instances can both pass the file-existence check before either writes its PID, resulting in both running simultaneously. On a fast machine or NFS, this window is exploitable and real.
- Fix: Replace with an atomic create-or-fail using `set -C` (noclobber) and redirect: `set -C; echo $$ > "$LOCK_FILE" 2>/dev/null || { echo "BOSS: concurrent gate running, skipping" >&2; exit 0; }; set +C`. This makes the create atomic without relying on a read-then-write sequence.

---

- File: hooks/stop-gate.sh
- Severity: HIGH
- Line: 43-46
- Problem: The PCRE grep (`grep -qP`) is used to check for unsafe characters in `$CWD`, but macOS ships with BSD grep which does not support `-P`. The `2>/dev/null` silently swallows the "invalid option" error, causing the whole guard to silently pass on macOS even for a malicious `$CWD`. REQ-010 requires Linux/Mac support, so this is a coverage gap on a supported platform.
- Fix: Replace the PCRE check with a POSIX-compatible one: `case "$CWD" in *[$'\000\n\r`$\\|;&<>']*)`. Alternatively use python3 (already a declared dependency) for the validation: `python3 -c "import sys; s=sys.argv[1]; exit(1 if any(c in s for c in '\x00\n\r\`$\\\\|;&<>') else 0)" "$CWD"`.

---

- File: hooks/stop-gate.sh
- Severity: MEDIUM
- Line: 88
- Problem: The world-writable check in `validate_python` is logically inverted. The condition `if [ -w "$candidate" ] && [ "$(stat ...)" != "$(whoami)" ]` fires only when the current user can write to the file AND the owner is someone else. A genuinely world-writable binary owned by root on a shared server satisfies this and is correctly rejected. However, a binary owned by the current user that is also world-writable (e.g., permissions 0777, owner=current user) passes the check because the `!=` comparison evaluates to false. The security intent — reject world-writable binaries regardless of owner — is not met.
- Fix: Check the file mode bits directly: `if [ "$(stat -c %a "$candidate" 2>/dev/null || stat -f %Lp "$candidate" 2>/dev/null)" != "${mode}" ]` where mode does not have the world-write bit set. Simpler: `if find "$candidate" -maxdepth 0 -perm /o+w 2>/dev/null | grep -q .; then echo "BOSS: world-writable python rejected" >&2; return 1; fi`.

---

- File: hooks/stop-gate.sh
- Severity: MEDIUM
- Line: 180-184
- Problem: The test failure reason is passed to python3 as a command-line argument (`sys.argv[1]`). On Linux/Mac, `ARG_MAX` limits the total argument size (typically 2 MB on Linux, 256 KB on macOS). A test suite that produces large output (e.g., many failures) will cause the python3 invocation to fail with "Argument list too long", silently falling through to `exit 0` — the gate fails open with no error message to stderr.
- Fix: Pass the combined output via stdin instead: `python3 -c "import sys,json; reason=sys.stdin.read(); print(json.dumps({'decision':'block','reason':'Tests failed:\n'+reason}))" <<< "$COMBINED"` or via a heredoc. This bypasses ARG_MAX entirely.

---

- File: hooks/stop-gate.ps1
- Severity: MEDIUM
- Line: 43
- Problem: The unsafe-character list includes `'"'` (double-quote), but Windows paths can legitimately contain no double-quotes, and the character is indeed disallowed in NTFS paths. However, the list omits the single-quote `'`. On PowerShell, single-quote has special meaning in some contexts. More critically, the backtick character `` ` `` is checked with `"`0"`, `"`n"`, etc. using PowerShell escape sequences — but when building the char array, `` '`' `` is listed as a bare backtick inside a single-quoted string. In PowerShell single-quoted strings, backtick is NOT an escape character, so the literal backtick char is included, which is correct. No bug here, but the comment is misleading. The real gap: forward-slash (`/`) in a path coming from WSL or mixed environments is not in the blocklist and could interact unexpectedly with Join-Path. This is LOW risk.
- Fix: Add `"'"` (single quote) to $unsafeChars to be consistent with the bash check.

---

- File: hooks/stop-gate.ps1
- Severity: LOW
- Line: 57
- Problem: `Test-Path $cwd -PathType Container` is called without quoting `$cwd`. If `$cwd` contains wildcard characters (`[`, `]`, `*`, `?`), PowerShell's `Test-Path` treats them as wildcards, potentially matching unintended paths or returning false negatives. The cwd character blocklist above does not block `[`, `]`, `*`, or `?`.
- Fix: Use `-LiteralPath` instead: `Test-Path -LiteralPath $cwd -PathType Container`. Apply the same to `Join-Path` calls downstream where paths are constructed from `$cwd`.

---

- File: hooks/stop-gate.ps1
- Severity: LOW
- Line: 96
- Problem: `& $candidate --version 2>&1` calls the candidate binary directly via the call operator. If `$candidate` contains spaces (e.g., `C:\Program Files\Python312\python.exe`) and is not quoted, the call operator handles this correctly in PowerShell — but if `$candidate` is somehow empty or null, the call operator will throw an unhandled exception that bypasses the `try/catch` block depending on the PS version.
- Fix: Add an explicit null/empty guard before the `& $candidate` call: `if (-not $candidate) { return $null }`. (The outer `if (-not $candidate ...)` on line 94 does this, but it tests the parameter not the resolved value — safe as-is but fragile if refactored.)

---

- File: scripts/patch-settings.py
- Severity: HIGH
- Line: 25
- Problem: `os.replace(tmp_path, path)` is documented as atomic on POSIX. On Windows, it is NOT atomic — it is implemented as `MoveFileExW` with `MOVEFILE_REPLACE_EXISTING`, which is a two-step delete-then-move at the OS level and is not crash-safe. More critically, `os.replace()` raises `OSError: [WinError 17] The system cannot move the file to a different disk drive` when `tmp_path` and `path` are on different drives. `tempfile.mkstemp(dir=dir_)` puts the temp file in the same directory as `path`, so same-drive is guaranteed — BUT only if `dir_` resolves correctly. If `path.parent` resolves to a network share mapped as a different drive letter than the temp dir default, this will still fail. The comment in the code acknowledges "same drive" but the logic relies on `dir=dir_` which is correct. The remaining gap is the non-atomicity on Windows under crash conditions, which is documented but accepted.
- Fix (for clarity): The code is correct for the cross-drive case since `dir=dir_` is used. Add an explicit note that Windows atomicity is best-effort. For truly atomic Windows writes, use `win32file.MoveFileEx` with `MOVEFILE_WRITE_THROUGH | MOVEFILE_REPLACE_EXISTING` — but this adds a dependency. Current behavior is acceptable for this use case; document it clearly.

---

- File: scripts/patch-settings.py
- Severity: MEDIUM
- Line: 81-84
- Problem: The idempotency check uses `any("stop-gate" in str(h).lower() or "boss" in str(h).lower() ...)`. `str(h)` on a dict produces Python repr like `{'type': 'command', 'command': '...'}`. This means the word "boss" being present anywhere in any hook dict — including in an unrelated hook's command path like `/home/bossanova/run.sh` — would suppress registration. The false-positive rate is low but nonzero, and the match is overly broad.
- Fix: Be explicit: check `h.get("command", "")` contains "stop-gate" or "boss/hooks": `any("stop-gate" in h.get("command","").lower() or "boss/hooks" in h.get("command","").lower() for entry in existing_list for h in entry.get("hooks",[]))`.

---

- File: install.sh
- Severity: HIGH
- Line: 116
- Problem: `curl -fsSL "$BOSS_REPO/$src" -o "$dst"` downloads files from a GitHub raw URL without any integrity check (no checksum, no GPG signature). If the GitHub account is compromised, or if a DNS/BGP hijack occurs, malicious hook scripts are silently installed and immediately granted execution permissions (line 121: `chmod +x`). The `-f` flag only fails on HTTP 4xx/5xx, not on content substitution.
- Fix: Pin downloads to a specific commit SHA in the URL and add a sha256 checksum verification step:
  ```bash
  EXPECTED_SHA="<known-sha256>"
  curl -fsSL "$BOSS_REPO/$src" -o "$dst"
  echo "$EXPECTED_SHA  $dst" | sha256sum -c - || { err "Checksum mismatch for $src"; exit 1; }
  ```
  Alternatively, ship a `checksums.txt` signed with a GPG key and verify against it.

---

- File: install.sh
- Severity: MEDIUM
- Line: 108
- Problem: `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"`. When the script is piped through bash (`curl ... | bash`), `BASH_SOURCE[0]` is empty or `/dev/stdin`, and `dirname ""` returns `.`, so `SCRIPT_DIR` becomes the current working directory rather than empty. This means the `copy_or_download` function will look for hook files relative to `$CWD` before falling back to curl — on a project that happens to have a `hooks/stop-gate.sh` file (e.g., its own hooks directory), the wrong file gets installed silently.
- Fix: When stdin-piped, `BASH_SOURCE[0]` is typically empty or `/dev/stdin`. Detect this explicitly:
  ```bash
  if [ -n "${BASH_SOURCE[0]:-}" ] && [ "${BASH_SOURCE[0]}" != "/dev/stdin" ]; then
      SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  else
      SCRIPT_DIR=""
  fi
  ```

---

- File: install.sh
- Severity: MEDIUM
- Line: 155 and 161
- Problem: `TEMPLATE_ARG` is constructed from user input (`read -r -p ... choice`) and then interpolated directly into a `copy_or_download` call as `"templates/$TEMPLATE_ARG.md"`. The `case` statement maps numeric choices to known strings, but if `--template=` is passed on the command line (line 22: `TEMPLATE_ARG="${arg#--template=}"`), the value is user-controlled raw input. A value like `../../../etc/passwd` or `../../.ssh/authorized_keys` would cause the curl download URL to be `$BOSS_REPO/../../../etc/passwd` (harmless against GitHub but bad pattern) or, in local mode, `cp "$SCRIPT_DIR/../../../etc/passwd" "$CWD/CLAUDE.md"`.
- Fix: Validate `TEMPLATE_ARG` against the known list before use:
  ```bash
  case "$TEMPLATE_ARG" in
      python-backend|node-api|fullstack|go-service|rust-crate|generic) ;;
      *) err "Invalid template: $TEMPLATE_ARG"; exit 1 ;;
  esac
  ```

---

- File: install.ps1
- Severity: MEDIUM
- Line: 124 and 130
- Problem: Same path traversal risk as install.sh. `$Template` can be passed via `-Template` parameter with arbitrary user-supplied value. It is used directly in `Copy-OrDownload "templates/$Template.md" $claudeMd` without validation against the known list. In local mode this allows copying arbitrary files from `$PSScriptRoot`.
- Fix: Add validation before use:
  ```powershell
  $validTemplates = @("python-backend","node-api","fullstack","go-service","rust-crate","generic")
  if ($Template -notin $validTemplates) { Write-Err "Invalid template: $Template"; exit 1 }
  ```

---

- File: install.ps1
- Severity: MEDIUM
- Line: 96
- Problem: `& python (Join-Path $BossDir "scripts\patch-settings.py") --platform win` uses `python` (not `python3`). On Windows, `python` may resolve to the Windows Store stub (`python.exe` that opens the Store), which returns exit code 9009. The install check on line 43 tests `python` not `python3`, which is consistent — but the Store stub passes `Get-Command` and then fails silently when invoked. There is no exit code check after the `patch-settings.py` invocation.
- Fix: Check `$LASTEXITCODE` after the python invocation:
  ```powershell
  & python (Join-Path $BossDir "scripts\patch-settings.py") --platform win
  if ($LASTEXITCODE -ne 0) { Write-Err "patch-settings.py failed (exit $LASTEXITCODE)"; exit 1 }
  ```
  Also consider checking for the Store stub by testing `(Get-Command python).Source` for `WindowsApps`.

---

- File: install.ps1
- Severity: LOW
- Line: 146
- Problem: The default CI file for the `default` branch of the switch is `"node"`, not `"generic"`. When `$Template` is `"generic"`, a Node CI template is copied. This is a logic bug — `generic` template should use `"generic"` CI file (if it exists) or the user should be warned that no matching CI template was found.
- Fix:
  ```powershell
  default { "generic" }
  ```
  and ensure a `ci-templates/generic.yml` exists.

---

## Correctness Bugs

---

- File: hooks/stop-gate.sh
- Severity: HIGH
- Line: 149
- Problem: `ls "$CWD"/test_*.py 2>/dev/null | head -1 | grep -q .` uses `ls` with a glob that expands in the shell. If `$CWD` contains spaces, the glob `"$CWD"/test_*.py` expands correctly (the outer quotes protect `$CWD`), but `ls` receives multiple arguments if glob matches multiple files — this is fine. However, if `$CWD` contains a `*` or `?` character that survives the earlier validation (the blocklist does not include these), the glob may expand unexpectedly. More practically: this `ls | head | grep` pipeline is unnecessary; use `[ -n "$(find "$CWD" -maxdepth 1 -name 'test_*.py' -print -quit 2>/dev/null)" ]` or a simple glob test.
- Fix: Replace with: `compgen -G "$CWD/test_*.py" > /dev/null 2>&1 && HAS_TESTS=true` or `if ls "$CWD"/test_*.py 2>/dev/null | grep -q .; then HAS_TESTS=true; fi` (the current form is functionally correct but fragile — document or simplify it).

---

- File: hooks/stop-gate.sh
- Severity: MEDIUM
- Line: 9-16
- Problem: `python3 -c "..." "$PAYLOAD"` passes the JSON payload as a command-line argument. If the payload contains single-quotes, the argument is still safe because it is passed as a positional argument to Python (not shell-interpolated). However, the PAYLOAD can be arbitrarily large (Claude conversations produce large JSON). On Linux, `ARG_MAX` is typically 2 MB. A payload exceeding this causes the python3 invocation to fail, `$STOP_HOOK_ACTIVE` silently defaults to `"false"`, and the gate runs a potentially infinite loop of blocking and retrying. REQ-004 requires this check to work reliably.
- Fix: Pass PAYLOAD via stdin to all python3 invocations:
  ```bash
  STOP_HOOK_ACTIVE=$(echo "$PAYLOAD" | python3 -c "
  import sys, json
  try:
      d = json.load(sys.stdin)
      print('true' if d.get('stop_hook_active') else 'false')
  except:
      print('false')
  " 2>/dev/null || echo "false")
  ```
  Apply the same fix to the CWD extraction python3 call on line 29.

---

- File: hooks/stop-gate.sh
- Severity: MEDIUM
- Line: 164
- Problem: `timeout 600 "${TEST_ARGS[@]}" >"$TMPOUT" 2>"$TMPERR"`. The `timeout` command is not available on macOS by default (it is part of GNU coreutils). On macOS, it is `gtimeout` (from homebrew) or absent. REQ-010 requires the hook to work on macOS. Without `timeout`, the test suite runs without a time limit and the hook hangs indefinitely.
- Fix: Detect and use the correct timeout command:
  ```bash
  TIMEOUT_CMD=""
  if command -v timeout >/dev/null 2>&1; then
      TIMEOUT_CMD="timeout 600"
  elif command -v gtimeout >/dev/null 2>&1; then
      TIMEOUT_CMD="gtimeout 600"
  fi
  ${TIMEOUT_CMD} "${TEST_ARGS[@]}" >"$TMPOUT" 2>"$TMPERR" || EXIT_CODE=$?
  ```
  If neither is available, run without timeout and log a warning.

---

- File: hooks/stop-gate.ps1
- Severity: MEDIUM
- Line: 155-162
- Problem: `Start-Process` with `-RedirectStandardOutput`/`-RedirectStandardError` does not inherit the parent process's environment. In particular, `$env:PATH` modifications made in the current session (e.g., venv activation, nvm, pyenv shims) are not visible to the child process. The test runner may fail to find the correct interpreter even though `$testExe` resolves correctly at detection time. Additionally, `Start-Process` with `-NoNewWindow` on Windows does not guarantee the child uses the same working directory encoding.
- Fix: Replace `Start-Process` with direct invocation using `&` operator combined with a job or `System.Diagnostics.Process` that explicitly inherits environment:
  ```powershell
  $psi = [System.Diagnostics.ProcessStartInfo]::new($testExe)
  $psi.Arguments = $testArgsList -join " "
  $psi.WorkingDirectory = $cwd
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  # Inherits current environment by default
  ```
  Or simpler: run tests via `&` and capture output to temp files using PowerShell redirection, which does inherit the environment.

---

- File: hooks/stop-gate.ps1
- Severity: LOW
- Line: 18
- Problem: `$rawInput = @($input) -join "`n"`. The `$input` automatic variable in a script that uses `param()` may behave differently depending on whether the script is called as a script block or a file. When called as `powershell -File stop-gate.ps1` with stdin piped, `$input` is populated lazily. The `@($input)` materialization works, but if the payload is multi-line JSON (which it will be for complex conversations), the join with `` "`n" `` is correct. However, if Claude Code pipes the payload as a single line (compact JSON), this is fine. If it pipes as pretty-printed JSON with Windows CRLF line endings, the `ConvertFrom-Json` on line 24 handles that correctly. Low risk but worth noting the assumption.
- Fix: No code change required, but add a comment: `# $input reads all piped stdin lines; join preserves multi-line JSON`.

---

- File: scripts/patch-settings.py
- Severity: MEDIUM
- Line: 71
- Problem: `boss_hook_entry` is constructed once and the same dict object is appended to both the `Stop` and `SubagentStop` lists. In Python, both list entries reference the same dict object. If any downstream code mutates the dict (unlikely in this script but a correctness hazard), both hook registrations would be affected. More practically, this means both events get the exact same `{"matcher":"","hooks":[...]}` entry, which is correct per requirements but is achieved by shared reference rather than two independent copies. If `changed=True` is set for both events, `existing_hooks["Stop"]` and `existing_hooks["SubagentStop"]` both contain the same object in memory.
- Fix: Use a deep copy: `import copy` and `existing_list.append(copy.deepcopy(boss_hook_entry))`.

---

- File: skills/verify/SKILL.md
- Severity: MEDIUM
- Line: 13 (git diff range)
- Problem: `git diff HEAD~10..HEAD` hardcodes a 10-commit lookback. If Agent 1's work spans more than 10 commits, Agent 2 silently misses earlier changes and produces an incomplete verification. The spec (REQ-037) says Agent 2 "reads only: .boss/spec.md + git diff + test commands" — it does not specify a range, but the hardcoded range means requirements implemented in commits earlier than HEAD~10 appear as unimplemented.
- Fix: Change to `git diff $(git merge-base HEAD main)..HEAD` (or `master`) to capture all commits since the branch diverged from main. Add a fallback: `git log --oneline | wc -l` to determine total commits and adjust range dynamically.

---

- File: skills/certify/SKILL.md
- Severity: LOW
- Line: 49 (JSON schema field name)
- Problem: The `certification.json` schema example uses `"certifier": "Agent 3"` but REQ-044 specifies the field must be named `"certifier_agent"`. The SKILL.md and the requirement are inconsistent. If Agent 3 uses the SKILL.md as its template (which it will), the output JSON will have `"certifier"` not `"certifier_agent"`, failing schema validation.
- Fix: Update the JSON example in SKILL.md line 49 to use `"certifier_agent": "Agent 3"` to match REQ-044.

---

## Missing Requirements Coverage

The following requirements from requirements.md have no identifiable implementation in the reviewed files:

---

- File: (none — not implemented)
- Severity: HIGH
- Line: N/A
- Problem: REQ-021 — "`npx @boss-claude/install` installs on any OS with Node" — there is no `package.json`, `index.js`, or npm package scaffold in the reviewed files. This install path does not exist.
- Fix: Create a minimal npm package with a `bin` entry that delegates to `install.sh` (on POSIX) or `install.ps1` (on Windows).

---

- File: (none — not implemented)
- Severity: HIGH
- Line: N/A
- Problem: REQ-025 — "Backs up settings.json to settings.json.bak before patching." The patch-settings.py creates timestamped backups (`settings.20260505T120000Z.bak`) which satisfies the spirit but not the letter. The requirement says `.bak` (singular, predictable name). If downstream tooling or documentation references `settings.json.bak` specifically, they will not find it. More importantly REQ-025 says "settings.json.bak" and the implementation produces `settings.TIMESTAMP.bak` — useful but non-conformant.
- Fix: Either update REQ-025 to explicitly accept timestamped backups, or additionally create a `settings.json.bak` symlink/copy to the latest backup.

---

- File: (none — not implemented)
- Severity: HIGH
- Line: N/A
- Problem: REQ-026 — "Detects project type, suggests matching CLAUDE.md template." Both installers detect the project type and default-select the matching template, but neither explicitly *suggests* it to the user and confirms before proceeding. In `--quiet` mode the selection is silent. In interactive mode, the detected type is logged but the template prompt does not pre-select the detected type as the default — it defaults to "6 (generic)" regardless of detection.
- Fix: In the interactive template selection, show the detected type as the pre-selected default: `"Choose [1-6] (default: python-backend, detected): "` and default to the detected type's number rather than always defaulting to 6.

---

- File: (none — not implemented)
- Severity: HIGH
- Line: N/A
- Problem: REQ-061 — "commit-msg hook enforces conventional commits format" — no `commit-msg` hook file exists in the reviewed file set.
- Fix: Create `hooks/commit-msg.sh` and `hooks/commit-msg.ps1` that validate the commit message against conventional commits format, and register them during install.

---

- File: (none — not implemented)
- Severity: HIGH
- Line: N/A
- Problem: REQ-062 — "pre-push hook runs test suite before every push" — no `pre-push` hook file exists in the reviewed file set.
- Fix: Create `hooks/pre-push.sh` and `hooks/pre-push.ps1` and register them during install.

---

- File: (none — not implemented)
- Severity: MEDIUM
- Line: N/A
- Problem: REQ-018 — "If hook itself crashes: fails open (exit 0), logs error." The bash hook uses `set -euo pipefail` (line 4), which means any uncaught error exits non-zero, not 0. There is no top-level `trap ... ERR` that catches unexpected errors and converts them to `exit 0`. Example: if `mktemp` fails (disk full), the script exits with a non-zero code which Claude Code interprets as a hard error, not as a graceful skip. The PS1 has a top-level `try/finally` but no `catch` on the outer block to convert crashes to exit 0.
- Fix (bash): Add a top-level error trap at the top of the script: `trap 'echo "BOSS: hook crashed unexpectedly, failing open" >&2; exit 0' ERR`. For PS1: wrap the entire body in `try { ... } catch { [Console]::Error.WriteLine("BOSS: hook crashed: $_"); exit 0 } finally { Remove-Lock }`.

---

- File: (none — not implemented)
- Severity: MEDIUM
- Line: N/A
- Problem: REQ-030 — "`--quiet` flag suppresses interactive prompts for CI/scripted use." The `install.sh` implements `--quiet` for interactive prompts. However, `patch-settings.py` (invoked from both installers) has no quiet mode and prints `"+ Adding BOSS hook to Stop"` etc. to stdout unconditionally. In a CI pipeline where stdout is parsed for errors, this extra output may be problematic, and the behavior is inconsistent with the `--quiet` contract.
- Fix: Pass `--quiet` through to `patch-settings.py` invocation and suppress its print statements when quiet.

---

- File: (none — not implemented)
- Severity: MEDIUM
- Line: N/A
- Problem: REQ-034 and REQ-035 — "Agent 1 writes `.boss/spec.md` and `.boss/testplan.md` before coding." There is no Builder skill (Agent 1 / `/build` or equivalent SKILL.md) in the reviewed file set. The pipeline requires 3 agents but only 2 skills (verify, certify) are provided.
- Fix: Create `skills/build/SKILL.md` that defines the Agent 1 role, spec.md format, testplan.md format, and the requirement that both files must be committed before any code is written.

---

- File: (none — not implemented)
- Severity: LOW
- Line: N/A
- Problem: REQ-043 — "Agent 3 writes `.boss/certification.json` matching schema at `.boss/schemas/certification.schema.json`." No schema file is provided or installed. Agent 3 is instructed to match this schema (certify/SKILL.md line 43) but the schema file does not exist, so Agent 3 cannot validate its own output against it.
- Fix: Create `.boss/schemas/certification.schema.json` and include it in the install.

---

- File: (none — not implemented)
- Severity: LOW
- Line: N/A
- Problem: REQ-012 — "SubagentStop hook registered separately." The `patch-settings.py` correctly registers the hook for both `Stop` and `SubagentStop`. However, the install scripts' log output says "Installing BOSS hooks..." but does not explicitly confirm that SubagentStop was registered (the python script output does, but only if the user reads it). REQ-NFR-008 requires every action to be logged/visible. Minor gap.
- Fix: The python script already prints per-event confirmation. This is covered. No change needed — close this gap.

---

## Summary

| Severity | Count |
|---|---|
| CRITICAL | 0 |
| HIGH | 7 |
| MEDIUM | 11 |
| LOW | 6 |
| **Total** | **24** |

### Top priorities (fix before shipping):

1. **Lockfile race condition** (stop-gate.sh:73) — use noclobber atomic create
2. **macOS grep -P silent failure** (stop-gate.sh:43) — replace with POSIX-compatible check
3. **ARG_MAX exceeded on large payloads** (stop-gate.sh:9, 180) — pass via stdin not argv
4. **curl install without checksum** (install.sh:116) — add sha256 verification
5. **Template path traversal** (install.sh:155, install.ps1:124) — validate against allowlist
6. **timeout not on macOS** (stop-gate.sh:164) — detect gtimeout fallback
7. **REQ-018 crash = fail open not enforced** (stop-gate.sh:4) — add ERR trap
8. **certifier vs certifier_agent field name mismatch** (certify/SKILL.md:49) — fix to match REQ-044
9. **git diff HEAD~10 hardcoded range** (verify/SKILL.md:13) — use merge-base
10. **REQ-061/062 hooks missing entirely** — commit-msg and pre-push not implemented
