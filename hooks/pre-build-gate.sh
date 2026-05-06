#!/usr/bin/env bash
# BOSS pre-build-gate.sh -- PreToolUse hook: blocks source writes until demo signoff exists
# Fires on Write, Edit, MultiEdit, NotebookEdit before Claude executes the tool.
# Requires: bash 3.2+, python3
set -euo pipefail

trap 'exit 0' ERR

# Read JSON payload from stdin
RAW_INPUT=$(cat)
if [ -z "$RAW_INPUT" ]; then exit 0; fi

# Emergency bypass
if [ "${BOSS_SKIP:-}" = "1" ]; then
    TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u)
    echo "BOSS: BOSS_SKIP=1 bypass active (audit: $TS)" >&2
    exit 0
fi

# Parse payload via python3 (jq optional)
CWD=$(printf '%s' "$RAW_INPUT" | python3 -c "
import sys, json
try:
    p = json.load(sys.stdin)
    print(p.get('cwd', ''))
except Exception:
    print('')
")

TOOL_NAME=$(printf '%s' "$RAW_INPUT" | python3 -c "
import sys, json
try:
    p = json.load(sys.stdin)
    print(p.get('tool_name', ''))
except Exception:
    print('')
")

FILE_PATH=$(printf '%s' "$RAW_INPUT" | python3 -c "
import sys, json
try:
    p = json.load(sys.stdin)
    ti = p.get('tool_input', {})
    # Write and Edit both use file_path
    print(ti.get('file_path', ''))
except Exception:
    print('')
")

if [ -z "$CWD" ] || [ -z "$TOOL_NAME" ]; then exit 0; fi

# Only intercept write-type tools
case "$TOOL_NAME" in
    Write|Edit|MultiEdit|NotebookEdit) ;;
    *) exit 0 ;;
esac

# Gate only active when spec.md exists (we are in a feature build)
SPEC_FILE="$CWD/.boss/spec.md"
if [ ! -f "$SPEC_FILE" ]; then exit 0; fi

# Gate clears once CEO has signed off
SIGNOFF_FILE="$CWD/.boss/demo-signoff.md"
if [ -f "$SIGNOFF_FILE" ]; then exit 0; fi

# Allow writes inside .boss/ — that's where demo artifacts go
if [ -n "$FILE_PATH" ]; then
    # Canonicalize .boss path
    BOSS_DIR=$(python3 -c "import os; print(os.path.realpath('$CWD/.boss'))")
    FILE_REAL=$(python3 -c "import os; print(os.path.realpath('$FILE_PATH'))" 2>/dev/null || echo "")
    if [ -n "$FILE_REAL" ]; then
        case "$FILE_REAL" in
            "$BOSS_DIR"*) exit 0 ;;  # inside .boss/, allow
        esac
    fi
fi

# Block — require CEO demo signoff
REASON="BOSS demo/signoff gate: .boss/demo-signoff.md not found.

Agent 1 must generate demo artifacts before writing source code:
  1. Write .boss/demo-artifacts/ (wireframe, API contract, or sequence diagram)
  2. Run /demo to generate them from spec.md
  3. CEO reviews artifacts and runs /signoff
  4. After .boss/demo-signoff.md is created, source code writes are unblocked.

To bypass this gate (emergency only):
  Set BOSS_SKIP=1"

printf '%s' "$REASON" | python3 -c "
import sys, json
reason = sys.stdin.read()
print(json.dumps({'decision': 'block', 'reason': reason}))
"
exit 0
