#!/usr/bin/env bash
# BOSS install.sh — one-command install for Linux/Mac
# Usage: curl -fsSL https://raw.githubusercontent.com/geemboombaa/boss-claude-code/master/install.sh | bash
# Or:    bash install.sh [--quiet] [--template=python] [--skip-ci]
set -euo pipefail

BOSS_VERSION="1.0.0"
BOSS_REPO="https://raw.githubusercontent.com/geemboombaa/boss-claude-code/master"
BOSS_DIR="$HOME/.claude/boss"
QUIET=false
TEMPLATE_ARG=""
SKIP_CI=false
DRY_RUN=false

# Parse args
for arg in "$@"; do
    case "$arg" in
        --quiet)       QUIET=true ;;
        --dry-run)     DRY_RUN=true ;;
        --skip-ci)     SKIP_CI=true ;;
        --template=*)  TEMPLATE_ARG="${arg#--template=}" ;;
    esac
done

log() { [ "$QUIET" = false ] && echo "$@" || true; }
err() { echo "ERROR: $@" >&2; }
confirm() {
    # In quiet mode, default yes
    [ "$QUIET" = true ] && return 0
    local prompt="$1"
    local response
    read -r -p "$prompt [Y/n] " response
    [[ "$response" =~ ^[Yy]$|^$ ]]
}

# Check Claude Code installed
if ! command -v claude >/dev/null 2>&1; then
    err "Claude Code is not installed."
    err "Install it from: https://claude.ai/code"
    exit 1
fi

# Check python3 available (needed for JSON patching)
if ! command -v python3 >/dev/null 2>&1; then
    err "python3 is required but not found."
    err "Install python3 and try again."
    exit 1
fi

log ""
log "BOSS -- Claude Code Enforcement Stack v$BOSS_VERSION"
log "============================================="
log ""

# Detect OS
OS="$(uname -s)"
case "$OS" in
    Darwin) OS_NAME="macOS" ;;
    Linux)  OS_NAME="Linux" ;;
    *)
        err "Unsupported OS: $OS. Use install.ps1 on Windows."
        exit 1
        ;;
esac
log "Detected: $OS_NAME"

# Detect project type
CWD=$(pwd)
PROJECT_TYPE="generic"
if [ -f "$CWD/pyproject.toml" ] || [ -f "$CWD/setup.py" ] || [ -f "$CWD/pytest.ini" ]; then
    PROJECT_TYPE="python-backend"
elif [ -f "$CWD/package.json" ]; then
    # Check if it's fullstack (has playwright.config)
    if [ -f "$CWD/playwright.config.ts" ] || [ -f "$CWD/playwright.config.js" ]; then
        PROJECT_TYPE="fullstack"
    else
        PROJECT_TYPE="node-api"
    fi
elif [ -f "$CWD/go.mod" ]; then
    PROJECT_TYPE="go-service"
elif [ -f "$CWD/Cargo.toml" ]; then
    PROJECT_TYPE="rust-crate"
fi
log "Detected: $PROJECT_TYPE project"

TESTS_EXIST=false
for testdir in "tests" "test" "__tests__" "spec"; do
    if [ -d "$CWD/$testdir" ]; then
        TESTS_EXIST=true
        break
    fi
done
[ "$TESTS_EXIST" = "true" ] && log "Detected: test directory found" || log "Note: no test directory found yet (BOSS will skip gate until tests exist)"

log ""

if [ "$DRY_RUN" = "true" ]; then
    log "DRY RUN -- no changes will be made"
    log "Would install to: $BOSS_DIR"
    exit 0
fi

# Create directories
log "Installing BOSS hooks..."
mkdir -p "$BOSS_DIR/hooks"

# Determine script location (running from curl or local)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"

copy_or_download() {
    local src="$1"
    local dst="$2"
    if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/$src" ]; then
        cp "$SCRIPT_DIR/$src" "$dst"
    else
        curl -fsSL "$BOSS_REPO/$src" -o "$dst"
    fi
}

copy_or_download "hooks/stop-gate.sh" "$BOSS_DIR/hooks/stop-gate.sh"
chmod +x "$BOSS_DIR/hooks/stop-gate.sh"
log "  Copied stop-gate.sh to $BOSS_DIR/hooks/"

copy_or_download "hooks/pre-build-gate.sh" "$BOSS_DIR/hooks/pre-build-gate.sh"
chmod +x "$BOSS_DIR/hooks/pre-build-gate.sh"
log "  Copied pre-build-gate.sh to $BOSS_DIR/hooks/"

copy_or_download "hooks/test-guard.sh" "$BOSS_DIR/hooks/test-guard.sh"
chmod +x "$BOSS_DIR/hooks/test-guard.sh"
log "  Copied test-guard.sh to $BOSS_DIR/hooks/"

copy_or_download "hooks/auto-push.ps1" "$BOSS_DIR/hooks/auto-push.ps1"
copy_or_download "hooks/auto-pr.ps1" "$BOSS_DIR/hooks/auto-pr.ps1"
copy_or_download "hooks/pre-push.ps1" "$BOSS_DIR/hooks/pre-push.ps1"
[ -f "$BOSS_DIR/hooks/auto-push.ps1" ] && log "  Copied auto-push.ps1 to $BOSS_DIR/hooks/"
[ -f "$BOSS_DIR/hooks/auto-pr.ps1" ]   && log "  Copied auto-pr.ps1 to $BOSS_DIR/hooks/"

copy_or_download "scripts/patch-settings.py" "$BOSS_DIR/scripts/patch-settings.py"

log ""
log "Patching ~/.claude/settings.json..."
python3 "$BOSS_DIR/scripts/patch-settings.py" --platform unix
log ""

# Template selection
if [ -z "$TEMPLATE_ARG" ] && [ "$QUIET" = false ]; then
    log "Project template:"
    log "  1) Python backend (FastAPI/Django/Flask + pytest)"
    log "  2) Node API (Express/Fastify + Jest/Vitest)"
    log "  3) Full-stack (frontend + backend + Playwright)"
    log "  4) Go service"
    log "  5) Rust crate"
    log "  6) Generic (any language)"
    read -r -p "Choose [1-6] (default 6): " choice
    case "${choice:-6}" in
        1) TEMPLATE_ARG="python-backend" ;;
        2) TEMPLATE_ARG="node-api" ;;
        3) TEMPLATE_ARG="fullstack" ;;
        4) TEMPLATE_ARG="go-service" ;;
        5) TEMPLATE_ARG="rust-crate" ;;
        *) TEMPLATE_ARG="generic" ;;
    esac
fi
[ -z "$TEMPLATE_ARG" ] && TEMPLATE_ARG="$PROJECT_TYPE"

# FIX ISSUE-005: validate template against allowlist (prevent path traversal)
VALID_TEMPLATES="python-backend node-api fullstack go-service rust-crate generic"
template_valid=false
for t in $VALID_TEMPLATES; do
    [ "$TEMPLATE_ARG" = "$t" ] && template_valid=true && break
done
if [ "$template_valid" = "false" ]; then
    err "Unknown template: '$TEMPLATE_ARG'. Valid options: $VALID_TEMPLATES"
    exit 1
fi

# Copy CLAUDE.md template
if [ -f "$CWD/CLAUDE.md" ]; then
    if confirm "CLAUDE.md already exists. Overwrite?"; then
        copy_or_download "templates/$TEMPLATE_ARG.md" "$CWD/CLAUDE.md"
        log "  Copied $TEMPLATE_ARG template to ./CLAUDE.md"
    else
        log "  Skipped CLAUDE.md (kept existing)"
    fi
else
    copy_or_download "templates/$TEMPLATE_ARG.md" "$CWD/CLAUDE.md"
    log "  Copied $TEMPLATE_ARG template to ./CLAUDE.md"
fi

# GitHub Actions CI
if [ "$SKIP_CI" = false ]; then
    if confirm "Set up GitHub Actions CI?"; then
        mkdir -p "$CWD/.github/workflows"
        # Map template to CI file
        CI_FILE="python"  # sensible default — has uv + pytest + artifacts
        case "$TEMPLATE_ARG" in
            python-backend) CI_FILE="python" ;;
            node-api)       CI_FILE="node" ;;
            fullstack)      CI_FILE="node" ;;
            go-service)     CI_FILE="go" ;;
            rust-crate)     CI_FILE="rust" ;;
            generic)        CI_FILE="python" ;;
        esac
        copy_or_download "ci-templates/$CI_FILE.yml" "$CWD/.github/workflows/test.yml"
        log "  Created .github/workflows/test.yml"
        if [ "$TEMPLATE_ARG" = "fullstack" ]; then
            copy_or_download "ci-templates/playwright.yml" "$CWD/.github/workflows/e2e.yml"
            log "  Created .github/workflows/e2e.yml (Playwright E2E)"
        fi
    fi
fi

# Install skills to ~/.claude/skills/ (Claude Code auto-discovers this path)
SKILLS_DIR="$HOME/.claude/skills"
for skill in build verify certify demo signoff run; do
    mkdir -p "$SKILLS_DIR/$skill"
    copy_or_download "skills/$skill/SKILL.md" "$SKILLS_DIR/$skill/SKILL.md"
done
log "  Installed /build, /verify, /certify, /demo, /signoff, /run → $SKILLS_DIR/"

# Install boss-delta.py to BOSS_DIR/scripts
mkdir -p "$BOSS_DIR/scripts"
copy_or_download "scripts/boss-delta.py" "$BOSS_DIR/scripts/boss-delta.py"
log "  Installed boss-delta.py → $BOSS_DIR/scripts/"

# Auto-install test runner dependencies
log ""
log "Checking test runner dependencies..."
case "$PROJECT_TYPE" in
    python-backend|generic)
        PYTHON_BIN=""
        for venv in .venv venv env; do
            if [ -f "$CWD/$venv/bin/python" ]; then
                PYTHON_BIN="$CWD/$venv/bin/python"
                break
            fi
        done
        [ -z "$PYTHON_BIN" ] && PYTHON_BIN="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || echo "")"
        if [ -n "$PYTHON_BIN" ]; then
            if ! "$PYTHON_BIN" -m pytest --version >/dev/null 2>&1; then
                log "  pytest not found — installing..."
                if command -v uv >/dev/null 2>&1 && [ -f "$CWD/pyproject.toml" ]; then
                    uv add --dev pytest --quiet && log "  Installed pytest via uv" || err "Could not install pytest via uv"
                else
                    "$PYTHON_BIN" -m pip install pytest --quiet && log "  Installed pytest via pip" || err "Could not install pytest"
                fi
            else
                log "  pytest: OK"
            fi
        else
            err "  python3 not found — install Python and then install pytest manually"
        fi
        ;;
    node-api|fullstack)
        if ! command -v node >/dev/null 2>&1; then
            err "  node not found — install Node.js from https://nodejs.org"
        else
            log "  node: OK ($(node --version))"
            if [ -f "$CWD/package.json" ]; then
                HAS_TEST=$(python3 -c "import json; d=json.load(open('$CWD/package.json')); print('yes' if d.get('scripts',{}).get('test') else 'no')" 2>/dev/null || echo "unknown")
                if [ "$HAS_TEST" = "no" ]; then
                    log "  WARNING: no 'test' script in package.json — stop hook will skip"
                fi
            fi
        fi
        ;;
    go-service)
        command -v go >/dev/null 2>&1 && log "  go: OK ($(go version | awk '{print $3}'))" || err "  go not found — install from https://go.dev"
        ;;
    rust-crate)
        command -v cargo >/dev/null 2>&1 && log "  cargo: OK" || err "  cargo not found — install from https://rustup.rs"
        ;;
esac

# Timing check: warn if test suite is slow (stop hook has 60s hard limit in some environments)
if [ "$TESTS_EXIST" = "true" ] && [ -n "${PYTHON_BIN:-}" ] && "$PYTHON_BIN" -m pytest --version >/dev/null 2>&1; then
    log ""
    log "Measuring test suite speed..."
    START_TS=$(date +%s 2>/dev/null || echo 0)
    "$PYTHON_BIN" -m pytest "$CWD" -q --co -q >/dev/null 2>&1 || true
    END_TS=$(date +%s 2>/dev/null || echo 0)
    COLLECT_SECS=$((END_TS - START_TS))
    if [ "$COLLECT_SECS" -gt 5 ] 2>/dev/null; then
        log "  WARNING: test collection took ${COLLECT_SECS}s — full suite may exceed 60s stop-hook limit"
        log "  Consider setting BOSS_TEST_CMD='pytest tests/unit -x' for a faster subset"
    else
        log "  Test collection: fast (${COLLECT_SECS}s)"
    fi
fi

log ""
log "============================================="
log "BOSS installed."
log "Claude cannot exit while your tests are red."
log "============================================="
log ""
log "Next steps:"
log "  1. Edit CLAUDE.md with your product vision"
log "  2. Run: claude"
log "  3. Type your first requirement"
log "  4. Walk away"
log ""
log "Verify it works:"
log "  Break a test, start Claude with any task."
log "  Claude should be blocked until you fix the test."
log ""
log "Emergency bypass (use sparingly):"
log "  BOSS_SKIP=1 claude"
log ""
