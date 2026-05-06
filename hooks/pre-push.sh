#!/usr/bin/env bash
# BOSS pre-push hook — runs tests before every git push
# Install: cp hooks/pre-push.sh .git/hooks/pre-push && chmod +x .git/hooks/pre-push
set -euo pipefail

if [ "${BOSS_SKIP:-}" = "1" ]; then
    echo "BOSS: BOSS_SKIP=1 set, skipping pre-push gate" >&2
    exit 0
fi

CWD=$(pwd)
PYTHON=""
TEST_CMD=""

detect_python() {
    for venv in ".venv" "venv" "env"; do
        if [ -f "$CWD/$venv/bin/python" ]; then PYTHON="$CWD/$venv/bin/python"; return; fi
        if [ -f "$CWD/$venv/Scripts/python.exe" ]; then PYTHON="$CWD/$venv/Scripts/python.exe"; return; fi
    done
    command -v python3 >/dev/null 2>&1 && PYTHON="python3" || PYTHON="python"
}

if [ -f "$CWD/pyproject.toml" ] || [ -f "$CWD/setup.py" ] || [ -f "$CWD/pytest.ini" ]; then
    detect_python
    TEST_CMD="$PYTHON -m pytest -q --tb=short --no-header --maxfail=5"
elif [ -f "$CWD/package.json" ]; then
    TEST_CMD="npm test --if-present"
elif [ -f "$CWD/go.mod" ]; then
    TEST_CMD="go test ./..."
elif [ -f "$CWD/Cargo.toml" ]; then
    TEST_CMD="cargo test --quiet"
fi

if [ -z "$TEST_CMD" ]; then
    echo "BOSS pre-push: no test suite detected, allowing push" >&2
    exit 0
fi

echo "BOSS pre-push: running tests before push..." >&2
if ! bash -c "$TEST_CMD"; then
    echo "BOSS pre-push: tests FAILED — push blocked" >&2
    echo "  Fix tests or set BOSS_SKIP=1 to bypass (use sparingly)" >&2
    exit 1
fi

echo "BOSS pre-push: tests passed" >&2
exit 0
