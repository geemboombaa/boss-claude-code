#!/usr/bin/env bash
# BOSS test-guard.sh -- PreToolUse hook: blocks edits to baseline test files
# Prevents AI from mutating pre-existing tests to make them pass.
# Requires: bash 3.2+, python3
set -euo pipefail
trap 'exit 0' ERR

RAW_INPUT=$(cat)
[ -z "$RAW_INPUT" ] && exit 0

if [ "${BOSS_SKIP:-}" = "1" ]; then exit 0; fi

# Parse payload fields
TOOL_NAME=$(printf '%s' "$RAW_INPUT" | python3 -c "
import sys, json
try: print(json.load(sys.stdin).get('tool_name',''))
except: print('')
" 2>/dev/null || echo "")

case "$TOOL_NAME" in
    Write|Edit|MultiEdit|NotebookEdit) ;;
    *) exit 0 ;;
esac

CWD=$(printf '%s' "$RAW_INPUT" | python3 -c "
import sys, json
try: print(json.load(sys.stdin).get('cwd',''))
except: print('')
" 2>/dev/null || echo "")

FILE_PATH=$(printf '%s' "$RAW_INPUT" | python3 -c "
import sys, json
try:
    p = json.load(sys.stdin)
    print(p.get('tool_input', {}).get('file_path', ''))
except: print('')
" 2>/dev/null || echo "")

[ -z "$CWD" ] || [ -z "$FILE_PATH" ] && exit 0

BOSS_DIR="$CWD/.boss"
BASELINE="$BOSS_DIR/baseline-tests.txt"
SESSION_LOCK="$BOSS_DIR/.baseline_session"

# Lazy baseline init: write once per session (keyed by session_id)
SESSION_ID=$(printf '%s' "$RAW_INPUT" | python3 -c "
import sys, json
try: print(json.load(sys.stdin).get('session_id',''))
except: print('')
" 2>/dev/null || echo "")

_NEEDS_BASELINE=false
if [ ! -f "$SESSION_LOCK" ]; then
    _NEEDS_BASELINE=true
elif [ -n "$SESSION_ID" ]; then
    _STORED=$(cat "$SESSION_LOCK" 2>/dev/null || echo "")
    [ "$_STORED" != "$SESSION_ID" ] && _NEEDS_BASELINE=true
fi

if [ "$_NEEDS_BASELINE" = "true" ]; then
    mkdir -p "$BOSS_DIR"
    # Collect all current test files
    {
        for _td in "tests" "test" "__tests__" "spec"; do
            [ -d "$CWD/$_td" ] && find "$CWD/$_td" -type f 2>/dev/null || true
        done
        find "$CWD" -maxdepth 3 \( -name "test_*.py" -o -name "*_test.py" \
             -o -name "*.test.ts" -o -name "*.test.js" -o -name "*.spec.ts" -o -name "*.spec.js" \
             -o -name "*_test.go" \) 2>/dev/null || true
    } | sort -u > "$BASELINE"
    echo "${SESSION_ID:-$(date +%s)}" > "$SESSION_LOCK"
fi

[ ! -f "$BASELINE" ] && exit 0

# Resolve file_path to absolute
FILE_ABS=$(python3 -c "
import os, sys
print(os.path.realpath(sys.argv[1]))
" "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")

# Block if file is in baseline
if grep -qxF "$FILE_ABS" "$BASELINE" 2>/dev/null; then
    REASON="BOSS test-guard: cannot edit pre-existing test file.

$FILE_ABS is in .boss/baseline-tests.txt (captured at session start).

AI agents have a perverse incentive to weaken tests to make them pass.
To add coverage: create a NEW test file alongside the existing one.
To legitimately modify this test (e.g. fix test setup): set BOSS_SKIP=1 (logged).
To reset the baseline: delete .boss/baseline-tests.txt and .boss/.baseline_session"

    printf '%s' "$REASON" | python3 -c "
import sys, json
print(json.dumps({'decision': 'block', 'reason': sys.stdin.read()}))
"
fi
exit 0
