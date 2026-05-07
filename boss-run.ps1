# boss-run.ps1 — CEO walkaway launcher
# CEO writes requirement, runs this script, walks away.
# Usage: .\boss-run.ps1 "Add rate limiting — 100 req/min per API key"
# Or:    .\boss-run.ps1   (reads requirement already in CLAUDE.md)
param(
    [string]$Requirement = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# Append requirement to CLAUDE.md if provided as argument
if ($Requirement) {
    $nl = [Environment]::NewLine
    Add-Content -Path "CLAUDE.md" -Value "${nl}## Requirement${nl}${Requirement}${nl}"
    Write-Host "[BOSS] Requirement written to CLAUDE.md"
}

# Verify CLAUDE.md exists
if (-not (Test-Path "CLAUDE.md")) {
    Write-Host "[BOSS] ERROR: CLAUDE.md not found. Write your requirement first." -ForegroundColor Red
    exit 1
}

# Verify claude CLI available
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claudeCmd) {
    Write-Host "[BOSS] ERROR: claude CLI not installed. Install from https://claude.ai/code" -ForegroundColor Red
    exit 1
}

if ($DryRun) {
    Write-Host "[BOSS] DRY RUN -- would run: claude -p '/run'"
    exit 0
}

Write-Host "[BOSS] Starting autonomous pipeline. CEO can walk away."
Write-Host "[BOSS] Progress tracked in .boss/run-plan.md"
Write-Host "[BOSS] Notification sent to BOSS_NOTIFY when CI completes."
Write-Host ""

# Run claude non-interactively with /run skill
claude -p "/run"
