# BOSS pre-build-gate.ps1 -- PreToolUse hook: blocks source writes until demo signoff exists
# Fires on Write, Edit, MultiEdit, NotebookEdit before Claude executes the tool.
# Requires: PowerShell 5.1+, python3
# ASCII-only strings throughout (CP1252 encoding constraint)

param()
$ErrorActionPreference = "Stop"

function Write-Err([string]$msg) {
    [Console]::Error.WriteLine("BOSS: $msg")
}

function Exit-Open([string]$reason) {
    Write-Err $reason
    exit 0
}

# Read JSON payload from stdin
$rawInput = @($input) -join "`n"
if (-not $rawInput -or $rawInput.Trim() -eq "") {
    exit 0
}

try {
    $payload = $rawInput | ConvertFrom-Json
} catch {
    exit 0
}

# Emergency bypass
if ($env:BOSS_SKIP -eq "1") {
    $ts = [System.DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    Exit-Open "BOSS_SKIP=1 bypass active (audit: $ts)"
}

$cwd = $payload.cwd
if (-not $cwd) { exit 0 }

$toolName = $payload.tool_name
if (-not $toolName) { exit 0 }

# Only intercept write-type tools
$writeTools = @("Write", "Edit", "MultiEdit", "NotebookEdit")
if ($writeTools -notcontains $toolName) { exit 0 }

# Gate only active when spec.md exists
$specFile = Join-Path $cwd ".boss\spec.md"
if (-not (Test-Path $specFile)) { exit 0 }

# Gate clears once CEO has signed off
$signoffFile = Join-Path $cwd ".boss\demo-signoff.md"
if (Test-Path $signoffFile) { exit 0 }

# Allow writes inside .boss/
$filePath = ""
if ($payload.tool_input) {
    $filePath = $payload.tool_input.file_path
    if (-not $filePath) { $filePath = "" }
}

if ($filePath) {
    try {
        $bossDir = [System.IO.Path]::GetFullPath((Join-Path $cwd ".boss"))
        $fileReal = [System.IO.Path]::GetFullPath($filePath)
        if ($fileReal.StartsWith($bossDir)) { exit 0 }
    } catch {}
}

# Block -- require CEO demo signoff
$reason = "BOSS demo/signoff gate: .boss/demo-signoff.md not found.`n`nAgent 1 must generate demo artifacts before writing source code:`n  1. Write .boss/demo-artifacts/ (wireframe, API contract, or sequence diagram)`n  2. Run /demo to generate them from spec.md`n  3. CEO reviews artifacts and runs /signoff`n  4. After .boss/demo-signoff.md is created, source code writes are unblocked.`n`nTo bypass this gate (emergency only):`n  Set BOSS_SKIP=1"

$json = [PSCustomObject]@{ decision = "block"; reason = $reason } | ConvertTo-Json -Compress
Write-Output $json
exit 0
