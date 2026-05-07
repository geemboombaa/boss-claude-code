# pre-push.ps1 — Windows pre-push gate
# Blocks git push if tests fail.
# Install: copy to .git/hooks/pre-push (no extension) and register via git config
param()

$ErrorActionPreference = "Continue"

# BOSS_SKIP bypass
if ($env:BOSS_SKIP -eq "1") {
    Write-Host "[BOSS pre-push] BOSS_SKIP=1 -- bypassed"
    exit 0
}

Write-Host "[BOSS pre-push] Running test suite before push..."

# Find python interpreter
$python = $null
foreach ($cmd in @("python", "python3", "py")) {
    if (Get-Command $cmd -ErrorAction SilentlyContinue) {
        $python = $cmd
        break
    }
}

if (-not $python) {
    Write-Host "[BOSS pre-push] WARNING: python not found -- skipping test gate"
    exit 0
}

# Run pytest
$result = & $python -m pytest -q --tb=short 2>&1
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    Write-Host "[BOSS pre-push] BLOCKED: tests failed -- fix before pushing."
    $result | ForEach-Object { Write-Host $_ }
    exit 1
}

Write-Host "[BOSS pre-push] Tests passed -- push allowed."
exit 0
