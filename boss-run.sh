#!/usr/bin/env bash
# boss-run.sh — CEO walkaway launcher
# CEO writes requirement, runs this script, walks away.
# Usage: ./boss-run.sh "Add rate limiting — 100 req/min per API key"
# Or:    ./boss-run.sh   (reads requirement already in CLAUDE.md)
set -e

REQUIREMENT="${1:-}"

# Append requirement to CLAUDE.md if provided as argument
if [ -n "$REQUIREMENT" ]; then
    printf "\n## Requirement\n%s\n" "$REQUIREMENT" >> CLAUDE.md
    echo "[BOSS] Requirement written to CLAUDE.md"
fi

# Verify CLAUDE.md exists
if [ ! -f CLAUDE.md ]; then
    echo "[BOSS] ERROR: CLAUDE.md not found. Write your requirement first." >&2
    exit 1
fi

# Verify claude CLI available
if ! command -v claude >/dev/null 2>&1; then
    echo "[BOSS] ERROR: claude CLI not installed. Install from https://claude.ai/code" >&2
    exit 1
fi

echo "[BOSS] Starting autonomous pipeline. CEO can walk away."
echo "[BOSS] Progress tracked in .boss/run-plan.md"
echo "[BOSS] Notification sent to BOSS_NOTIFY when CI completes."
echo ""

# Run claude non-interactively with /run skill
claude -p "/run"
