#!/usr/bin/env bash
# BOSS stop-gate.sh — blocks Claude response when tests fail
# Requires: bash 3.2+, python3
set -uo pipefail

# FIX ISSUE-007: crash = fail open
trap 'rc=$?; echo "BOSS: hook crashed (rc=$rc), failing open" >&2; exit 0' ERR

# FIX ISSUE-003: ARG_MAX — read payload once, pass via stdin to python everywhere
PAYLOAD=$(cat)

# Prevent infinite loop — pass via stdin (not arg) to avoid ARG_MAX
STOP_HOOK_ACTIVE=$(printf '%s' "$PAYLOAD" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print('true' if d.get('stop_hook_active') else 'false')
except Exception:
    print('false')
" 2>/dev/null || echo "false")

if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    exit 0
fi

# Emergency bypass (logged)
if [ "${BOSS_SKIP:-}" = "1" ]; then
    echo "BOSS: BOSS_SKIP=1 bypass active (audit: $(date -u +%Y-%m-%dT%H:%M:%SZ))" >&2
    exit 0
fi

# Get cwd from payload via stdin
CWD=$(printf '%s' "$PAYLOAD" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('cwd', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")

if [ -z "$CWD" ]; then
    echo "BOSS: cwd empty in payload, skipping" >&2
    exit 0
fi

# FIX ISSUE-002: validate cwd via python3 (not grep -P — absent on macOS BSD grep)
SAFE=$(printf '%s' "$CWD" | python3 -c "
import sys, re
cwd = sys.stdin.read()
if re.search(r'[\x00\n\r\`\$|;&<>]', cwd):
    print('no')
else:
    print('yes')
" 2>/dev/null || echo "no")

if [ "$SAFE" != "yes" ]; then
    echo "BOSS: cwd contains unsafe characters, skipping" >&2
    exit 0
fi

# Canonicalize
CWD=$(python3 -c "
import os, sys
p = os.path.realpath(sys.argv[1])
print(p if os.path.isdir(p) else '')
" "$CWD" 2>/dev/null || echo "")

if [ -z "$CWD" ] || [ ! -d "$CWD" ]; then
    echo "BOSS: cwd not a real directory, skipping" >&2
    exit 0
fi

# FIX ISSUE-001: atomic lockfile with noclobber (prevents race condition)
BOSS_DIR="$CWD/.boss"
mkdir -p "$BOSS_DIR"
LOCK_FILE="$BOSS_DIR/.gate_running"

if ( set -C; echo $$ > "$LOCK_FILE" ) 2>/dev/null; then
    : # acquired lock
else
    # Lock exists — check if owning process is alive
    LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
        echo "BOSS: concurrent gate running (PID $LOCK_PID), skipping" >&2
        exit 0
    else
        # Stale — take over
        rm -f "$LOCK_FILE"
        echo $$ > "$LOCK_FILE"
    fi
fi

cleanup() { rm -f "$LOCK_FILE" "${TMPOUT:-}" "${TMPERR:-}"; }
trap cleanup EXIT

# Language detection + test command (arrays — no shell injection)
PYTHON=""
declare -a TEST_ARGS=()

validate_python() {
    local candidate="$1"
    [ -f "$candidate" ] && [ -x "$candidate" ] || return 1
    "$candidate" --version 2>&1 | grep -qiE 'python [23]\.[0-9]' || return 1
    return 0
}

detect_python() {
    for venv in ".venv" "venv" "env"; do
        for py_path in "$CWD/$venv/bin/python" "$CWD/$venv/Scripts/python.exe"; do
            if validate_python "$py_path" 2>/dev/null; then
                PYTHON="$py_path"; return
            fi
        done
    done
    for cmd in python3 python; do
        local py_bin
        py_bin=$(command -v "$cmd" 2>/dev/null || echo "")
        if [ -n "$py_bin" ] && validate_python "$py_bin" 2>/dev/null; then
            PYTHON="$py_bin"; return
        fi
    done
    echo "BOSS: no valid python found" >&2
}

if [ -f "$CWD/pyproject.toml" ] || [ -f "$CWD/setup.py" ] || \
   [ -f "$CWD/pytest.ini" ] || [ -f "$CWD/setup.cfg" ]; then
    detect_python
    [ -z "$PYTHON" ] && exit 0
    TEST_ARGS=("$PYTHON" "-m" "pytest" "-q" "--tb=short" "--no-header" "--maxfail=5")
elif [ -f "$CWD/package.json" ]; then
    TEST_ARGS=("npm" "test" "--if-present")
elif [ -f "$CWD/go.mod" ]; then
    TEST_ARGS=("go" "test" "./...")
elif [ -f "$CWD/Cargo.toml" ]; then
    TEST_ARGS=("cargo" "test" "--quiet")
fi

if [ ${#TEST_ARGS[@]} -eq 0 ]; then
    echo "BOSS: no test suite detected, skipping" >&2
    exit 0
fi

# Check tests exist
HAS_TESTS=false
for testdir in "tests" "test" "__tests__" "spec" "src/__tests__"; do
    [ -d "$CWD/$testdir" ] && HAS_TESTS=true && break
done
if [ "$HAS_TESTS" = "false" ] && ls "$CWD"/test_*.py 2>/dev/null | head -1 | grep -q .; then
    HAS_TESTS=true
fi
if [ "$HAS_TESTS" = "false" ]; then
    echo "BOSS: no test files found, skipping gate" >&2
    exit 0
fi

# FIX ISSUE-006: detect timeout command (absent on macOS without homebrew)
TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_CMD="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_CMD="gtimeout"
else
    echo "BOSS: timeout command not found, running without time limit" >&2
fi

TMPOUT=$(mktemp)
TMPERR=$(mktemp)
cd "$CWD"
EXIT_CODE=0

if [ -n "$TIMEOUT_CMD" ]; then
    $TIMEOUT_CMD 600 "${TEST_ARGS[@]}" >"$TMPOUT" 2>"$TMPERR" || EXIT_CODE=$?
    if [ $EXIT_CODE -eq 124 ]; then
        echo "BOSS: test suite timed out after 10 minutes, failing open" >&2
        exit 0
    fi
else
    "${TEST_ARGS[@]}" >"$TMPOUT" 2>"$TMPERR" || EXIT_CODE=$?
fi

STDOUT=$(cat "$TMPOUT")
STDERR=$(cat "$TMPERR")

if [ $EXIT_CODE -ne 0 ]; then
    echo "BOSS: tests FAILED — blocking Claude response" >&2
    echo "$STDOUT" >&2
    echo "$STDERR" >&2
    COMBINED="${STDOUT}
${STDERR}"
    # FIX ISSUE-003: pass output via stdin to avoid ARG_MAX on large test output
    printf '%s' "$COMBINED" | python3 -c "
import sys, json
output = sys.stdin.read()
print(json.dumps({'decision': 'block', 'reason': 'Tests failed:\n' + output}))
"
    exit 0
fi

echo "BOSS: tests passed — allowing response" >&2
exit 0
