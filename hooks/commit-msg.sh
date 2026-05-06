#!/usr/bin/env bash
# BOSS commit-msg hook — enforces conventional commits
# Install: cp hooks/commit-msg.sh .git/hooks/commit-msg && chmod +x .git/hooks/commit-msg
set -euo pipefail

MSG_FILE="$1"
MSG=$(cat "$MSG_FILE")

PATTERN="^(feat|fix|docs|test|refactor|chore|ci|perf|style|build|revert)(\(.+\))?: .{1,72}"

if ! echo "$MSG" | grep -qE "$PATTERN"; then
    echo "BOSS commit-msg: commit message must follow conventional commits format" >&2
    echo "  Pattern: type(scope): description" >&2
    echo "  Types:   feat|fix|docs|test|refactor|chore|ci|perf|style|build|revert" >&2
    echo "  Example: feat(hooks): add stop-gate language detection" >&2
    echo "" >&2
    echo "  Your message: $MSG" >&2
    exit 1
fi

exit 0
