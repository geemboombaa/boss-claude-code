# BOSS stop-gate.ps1 -- blocks Claude response when tests fail
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
    Exit-Open "empty payload, skipping"
}

try {
    $payload = $rawInput | ConvertFrom-Json
} catch {
    Exit-Open "invalid JSON payload, skipping"
}

# Prevent infinite loop
if ($payload.stop_hook_active) { exit 0 }

# Emergency bypass (logged)
if ($env:BOSS_SKIP -eq "1") {
    $ts = [System.DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    Exit-Open "BOSS_SKIP=1 bypass active -- gate skipped (audit: $ts)"
}

# Get cwd from payload (never $PWD)
$cwd = $payload.cwd
if (-not $cwd) { Exit-Open "cwd empty in payload, skipping" }

# FIX ISSUE-001: validate cwd -- reject null bytes, newlines, shell metacharacters
$unsafeChars = [char[]]@("`0", "`n", "`r", '`', '$', '|', ';', '&', '<', '>', '"')
foreach ($c in $unsafeChars) {
    if ($cwd.Contains([string]$c)) {
        Exit-Open "cwd contains unsafe characters, skipping"
    }
}

# Canonicalize path
try {
    $cwd = [System.IO.Path]::GetFullPath($cwd)
} catch {
    Exit-Open "could not canonicalize cwd, skipping"
}

if (-not (Test-Path $cwd -PathType Container)) {
    Exit-Open "cwd not a real directory, skipping"
}

# PID-based lockfile (FIX ISSUE-003)
$bossDir = Join-Path $cwd ".boss"
if (-not (Test-Path $bossDir)) {
    New-Item -ItemType Directory -Path $bossDir -Force | Out-Null
}
$lockFile = Join-Path $bossDir ".gate_running"

if (Test-Path $lockFile) {
    $lockPid = Get-Content $lockFile -ErrorAction SilentlyContinue
    $processAlive = $false
    if ($lockPid) {
        try {
            $proc = Get-Process -Id ([int]$lockPid) -ErrorAction SilentlyContinue
            $processAlive = ($proc -ne $null)
        } catch { $processAlive = $false }
    }
    if ($processAlive) {
        Exit-Open "concurrent gate already running (PID $lockPid), skipping"
    } else {
        Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
    }
}

$currentPid = $PID
Set-Content -Path $lockFile -Value $currentPid -NoNewline

function Remove-Lock {
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
}

try {
    # FIX ISSUE-002: validate Python binary before executing
    function Get-ValidPython([string]$candidate) {
        if (-not $candidate -or -not (Test-Path $candidate -PathType Leaf)) { return $null }
        try {
            $out = & $candidate --version 2>&1
            if ($out -match 'Python [23]\.\d') { return $candidate }
        } catch {}
        return $null
    }

    # Language detection
    $testExe = $null
    $testArgsList = @()

    $isPython = (Test-Path (Join-Path $cwd "pyproject.toml")) -or
                (Test-Path (Join-Path $cwd "setup.py")) -or
                (Test-Path (Join-Path $cwd "pytest.ini")) -or
                (Test-Path (Join-Path $cwd "setup.cfg"))
    $isNode = Test-Path (Join-Path $cwd "package.json")
    $isGo   = Test-Path (Join-Path $cwd "go.mod")
    $isRust = Test-Path (Join-Path $cwd "Cargo.toml")

    if ($isPython) {
        $python = $null
        foreach ($venv in @(".venv", "venv", "env")) {
            $winPy = Join-Path $cwd "$venv\Scripts\python.exe"
            $nixPy = Join-Path $cwd "$venv/bin/python"
            $python = Get-ValidPython $winPy
            if (-not $python) { $python = Get-ValidPython $nixPy }
            if ($python) { break }
        }
        if (-not $python) {
            foreach ($cmd in @("python3", "python")) {
                $sysPath = (Get-Command $cmd -ErrorAction SilentlyContinue)?.Source
                $python = Get-ValidPython $sysPath
                if ($python) { break }
            }
        }
        if (-not $python) { Exit-Open "no valid python found, skipping" }
        $testExe = $python
        $testArgsList = @("-m", "pytest", "-q", "--tb=short", "--no-header", "--maxfail=5")
    }
    elseif ($isNode)  { $testExe = "npm";   $testArgsList = @("test", "--if-present") }
    elseif ($isGo)    { $testExe = "go";    $testArgsList = @("test", "./...") }
    elseif ($isRust)  { $testExe = "cargo"; $testArgsList = @("test", "--quiet") }
    else { Exit-Open "no test suite detected, skipping" }

    # Check tests exist
    $testDirs = @("tests", "test", "__tests__", "spec")
    $hasTests = $false
    foreach ($d in $testDirs) {
        if (Test-Path (Join-Path $cwd $d) -PathType Container) { $hasTests = $true; break }
    }
    if (-not $hasTests) {
        $hasTests = (Get-ChildItem -Path $cwd -Filter "test_*.py" -ErrorAction SilentlyContinue |
                     Select-Object -First 1) -ne $null
    }
    if (-not $hasTests) { Exit-Open "no test files found, skipping gate" }

    # Run with 10-minute timeout
    $tmpOut = [System.IO.Path]::GetTempFileName()
    $tmpErr = [System.IO.Path]::GetTempFileName()

    $proc = Start-Process `
        -FilePath $testExe `
        -ArgumentList $testArgsList `
        -WorkingDirectory $cwd `
        -RedirectStandardOutput $tmpOut `
        -RedirectStandardError $tmpErr `
        -NoNewWindow `
        -PassThru

    $completed = $proc.WaitForExit(600000)

    if (-not $completed) {
        $proc.Kill()
        Remove-Item $tmpOut, $tmpErr -Force -ErrorAction SilentlyContinue
        Exit-Open "test suite timed out after 10 minutes, failing open"
    }

    $stdout = Get-Content $tmpOut -Raw -ErrorAction SilentlyContinue
    $stderr = Get-Content $tmpErr -Raw -ErrorAction SilentlyContinue
    Remove-Item $tmpOut, $tmpErr -Force -ErrorAction SilentlyContinue

    if ($proc.ExitCode -ne 0) {
        Write-Err "tests FAILED -- blocking Claude response"
        if ($stdout) { [Console]::Error.WriteLine($stdout) }
        if ($stderr) { [Console]::Error.WriteLine($stderr) }
        $combined = "$stdout`n$stderr"
        # Sanitize to ASCII (CP1252 safety)
        $combined = [System.Text.RegularExpressions.Regex]::Replace($combined, '[^\x20-\x7E\r\n\t]', '?')
        $reason = "Tests failed:`n$combined"
        $json = [PSCustomObject]@{ decision = "block"; reason = $reason } | ConvertTo-Json -Compress
        Write-Output $json
        exit 0
    }

    Write-Err "tests passed -- allowing response"
    exit 0
}
finally {
    Remove-Lock
}
