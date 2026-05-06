#!/usr/bin/env bash
# BOSS stop-gate.sh — blocks Claude response when tests fail
# Requires: bash 3.2+, python3
set -euo pipefail

PAYLOAD=$(cat)

# Prevent infinite loop — exit immediately if already in forced-continuation
STOP_HOOK_ACTIVE=$(python3 -c "
import sys, json
try:
    d = json.loads(sys.argv[1])
    print('true' if d.get('stop_hook_active') else 'false')
except:
    print('false')
" "$PAYLOAD" 2>/dev/null || echo "false")

if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    exit 0
fi

# Emergency bypass (logged — not silent)
if [ "${BOSS_SKIP:-}" = "1" ]; then
    echo "BOSS: BOSS_SKIP=1 bypass active — gate skipped (audit: $(date -u +%Y-%m-%dT%H:%M:%SZ))" >&2
    exit 0
fi

# Get cwd from payload (never use $PWD — Claude's cwd may differ)
CWD=$(python3 -c "
import sys, json
try:
    d = json.loads(sys.argv[1])
    print(d.get('cwd', ''))
except:
    print('')
" "$PAYLOAD" 2>/dev/null || echo "")

# FIX ISSUE-001: validate cwd before use — reject null bytes, newlines, suspicious metacharacters
if [ -z "$CWD" ]; then
    echo "BOSS: cwd empty in payload, skipping" >&2
    exit 0
fi
if printf '%s' "$CWD" | grep -qP '[\x00\n\r`$\\|;&<>]' 2>/dev/null || \
   printf '%s' "$CWD" | grep -q $'\n'; then
    echo "BOSS: cwd contains unsafe characters, skipping" >&2
    exit 0
fi
# Canonicalize to real path
CWD=$(python3 -c "import os,sys; p=os.path.realpath(sys.argv[1]); print(p) if os.path.isdir(p) else print('')" "$CWD" 2>/dev/null || echo "")
if [ -z "$CWD" ] || [ ! -d "$CWD" ]; then
    echo "BOSS: cwd not a real directory, skipping" >&2
    exit 0
fi

# Lockfile — PID-based to detect stale locks (FIX ISSUE-003)
BOSS_DIR="$CWD/.boss"
mkdir -p "$BOSS_DIR"
LOCK_FILE="$BOSS_DIR/.gate_running"

if [ -f "$LOCK_FILE" ]; then
    LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    LOCK_AGE=0
    if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
        # Process is alive — genuine concurrent run, skip
        echo "BOSS: concurrent gate already running (PID $LOCK_PID), skipping" >&2
        exit 0
    else
        # Stale lock — clean up
        rm -f "$LOCK_FILE"
    fi
fi

echo $$ > "$LOCK_FILE"
cleanup() { rm -f "$LOCK_FILE" "${TMPOUT:-}" "${TMPERR:-}"; }
trap cleanup EXIT

# Language detection + test command (as arrays to prevent injection — FIX ISSUE-001)
PYTHON=""
declare -a TEST_ARGS=()

validate_python() {
    local candidate="$1"
    # FIX ISSUE-002: verify binary is actually Python before executing
    if [ ! -f "$candidate" ] || [ ! -x "$candidate" ]; then
        return 1
    fi
    # World-writable check (would allow privilege escalation)
    if [ -w "$candidate" ] && [ "$(stat -c %U "$candidate" 2>/dev/null || stat -f %Su "$candidate" 2>/dev/null)" != "$(whoami)" ]; then
        echo "BOSS: venv python is world-writable, rejecting (security)" >&2
        return 1
    fi
    local version_output
    version_output=$("$candidate" --version 2>&1 || echo "")
    if ! echo "$version_output" | grep -qiE '^python [23]\.[0-9]'; then
        echo "BOSS: $candidate does not appear to be Python, rejecting" >&2
        return 1
    fi
    return 0
}

detect_python() {
    for venv in ".venv" "venv" "env"; do
        for py_path in "$CWD/$venv/bin/python" "$CWD/$venv/Scripts/python.exe"; do
            if validate_python "$py_path" 2>/dev/null; then
                PYTHON="$py_path"
                return
            fi
        done
    done
    # Fall back to system python
    for cmd in python3 python; do
        local py_bin
        py_bin=$(command -v "$cmd" 2>/dev/null || echo "")
        if [ -n "$py_bin" ] && validate_python "$py_bin" 2>/dev/null; then
            PYTHON="$py_bin"
            return
        fi
    done
    echo "BOSS: no valid python found" >&2
}

if [ -f "$CWD/pyproject.toml" ] || [ -f "$CWD/setup.py" ] || [ -f "$CWD/pytest.ini" ] || [ -f "$CWD/setup.cfg" ]; then
    detect_python
    if [ -z "$PYTHON" ]; then
        exit 0
    fi
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
    if [ -d "$CWD/$testdir" ]; then
        HAS_TESTS=true
        break
    fi
done
if [ "$HAS_TESTS" = "false" ] && ls "$CWD"/test_*.py 2>/dev/null | head -1 | grep -q .; then
    HAS_TESTS=true
fi

if [ "$HAS_TESTS" = "false" ]; then
    echo "BOSS: no test files found, skipping gate" >&2
    exit 0
fi

# Run tests with 10-minute timeout using arrays (no string injection)
TMPOUT=$(mktemp)
TMPERR=$(mktemp)

cd "$CWD"
EXIT_CODE=0
timeout 600 "${TEST_ARGS[@]}" >"$TMPOUT" 2>"$TMPERR" || EXIT_CODE=$?

if [ $EXIT_CODE -eq 124 ]; then
    echo "BOSS: test suite timed out after 10 minutes, failing open" >&2
    exit 0
fi

STDOUT=$(cat "$TMPOUT")
STDERR=$(cat "$TMPERR")

if [ $EXIT_CODE -ne 0 ]; then
    echo "BOSS: tests FAILED — blocking Claude response" >&2
    echo "$STDOUT" >&2
    echo "$STDERR" >&2
    COMBINED="${STDOUT}
${STDERR}"
    python3 -c "
import sys, json
reason = sys.argv[1]
print(json.dumps({'decision': 'block', 'reason': 'Tests failed:\n' + reason}))
" "$COMBINED"
    exit 0
fi

echo "BOSS: tests passed — allowing response" >&2
exit 0
