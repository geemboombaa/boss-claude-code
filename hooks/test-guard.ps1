# BOSS test-guard.ps1 -- PreToolUse hook: blocks edits to baseline test files
# Prevents AI from mutating pre-existing tests to make them pass.
# Requires: PowerShell 5.1+, python3
# ASCII-only strings throughout (CP1252 encoding constraint)

param()
$ErrorActionPreference = "Stop"

function Write-Err([string]$msg) { [Console]::Error.WriteLine("BOSS: $msg") }
function Exit-Open([string]$reason) { Write-Err $reason; exit 0 }

$rawInput = @($input) -join "`n"
if (-not $rawInput -or $rawInput.Trim() -eq "") { exit 0 }

try { $payload = $rawInput | ConvertFrom-Json } catch { exit 0 }

if ($env:BOSS_SKIP -eq "1") { exit 0 }

$toolName = $payload.tool_name
if (-not $toolName) { exit 0 }
$writeTools = @("Write", "Edit", "MultiEdit", "NotebookEdit")
if ($writeTools -notcontains $toolName) { exit 0 }

$cwd = $payload.cwd
if (-not $cwd) { exit 0 }

$filePath = ""
if ($payload.tool_input) {
    $filePath = $payload.tool_input.file_path
    if (-not $filePath) { $filePath = "" }
}
if (-not $filePath) { exit 0 }

$bossDir = Join-Path $cwd ".boss"
$baseline = Join-Path $bossDir "baseline-tests.txt"
$sessionLock = Join-Path $bossDir ".baseline_session"

# Lazy baseline init: write once per session (keyed by session_id)
$sessionId = if ($payload.session_id) { $payload.session_id } else { "" }
$needsBaseline = $false

if (-not (Test-Path $sessionLock)) {
    $needsBaseline = $true
} elseif ($sessionId) {
    $stored = Get-Content $sessionLock -ErrorAction SilentlyContinue
    if ($stored -ne $sessionId) { $needsBaseline = $true }
}

if ($needsBaseline) {
    New-Item -ItemType Directory -Path $bossDir -Force | Out-Null
    $testFiles = @()
    foreach ($td in @("tests", "test", "__tests__", "spec")) {
        $tdPath = Join-Path $cwd $td
        if (Test-Path $tdPath) {
            $testFiles += Get-ChildItem -Path $tdPath -Recurse -File -ErrorAction SilentlyContinue |
                          Select-Object -ExpandProperty FullName
        }
    }
    # Also find test_*.py, *_test.py, *.test.ts etc up to 3 levels deep
    $patterns = @("test_*.py", "*_test.py", "*.test.ts", "*.test.js", "*.spec.ts", "*.spec.js", "*_test.go")
    foreach ($pat in $patterns) {
        $testFiles += Get-ChildItem -Path $cwd -Filter $pat -Recurse -Depth 3 -File -ErrorAction SilentlyContinue |
                      Select-Object -ExpandProperty FullName
    }
    $testFiles | Sort-Object -Unique | Set-Content -Path $baseline -Encoding UTF8
    $lockVal = if ($sessionId -ne "") { $sessionId } else { [string][DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
    Set-Content -Path $sessionLock -Value $lockVal -Encoding UTF8
}

if (-not (Test-Path $baseline)) { exit 0 }

# Resolve file path
try {
    $fileAbs = [System.IO.Path]::GetFullPath($filePath)
} catch {
    $fileAbs = $filePath
}

# Block if file is in baseline
$baselineContent = Get-Content $baseline -ErrorAction SilentlyContinue
if ($baselineContent -contains $fileAbs) {
    $reason = "BOSS test-guard: cannot edit pre-existing test file.`n`n$fileAbs is in .boss/baseline-tests.txt (captured at session start).`n`nAI agents have a perverse incentive to weaken tests to make them pass.`nTo add coverage: create a NEW test file alongside the existing one.`nTo legitimately modify this test: set BOSS_SKIP=1 (logged).`nTo reset the baseline: delete .boss/baseline-tests.txt and .boss/.baseline_session"
    $json = [PSCustomObject]@{ decision = "block"; reason = $reason } | ConvertTo-Json -Compress
    Write-Output $json
}
exit 0
