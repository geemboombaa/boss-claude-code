# BOSS install.ps1 -- Windows installer
# Usage: iwr https://raw.githubusercontent.com/geemboombaa/boss-claude-code/master/install.ps1 | iex
# Or:    .\install.ps1 [-Quiet] [-Template python] [-SkipCI] [-DryRun]
param(
    [switch]$Quiet,
    [string]$Template = "",
    [switch]$SkipCI,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$BossVersion = "1.0.0"
$BossRepo = "https://raw.githubusercontent.com/geemboombaa/boss-claude-code/master"
$BossDir = Join-Path $HOME ".claude\boss"

function Write-Log([string]$msg) { if (-not $Quiet) { Write-Host $msg } }
function Write-Err([string]$msg) { [Console]::Error.WriteLine("ERROR: $msg") }

function Confirm-Action([string]$prompt) {
    if ($Quiet) { return $true }
    $r = Read-Host "$prompt [Y/n]"
    return ($r -match '^[Yy]$' -or $r -eq "")
}

function Copy-OrDownload([string]$src, [string]$dst) {
    $scriptDir = $PSScriptRoot
    $localSrc = if ($scriptDir) { Join-Path $scriptDir $src } else { "" }
    if ($localSrc -and (Test-Path $localSrc)) {
        Copy-Item $localSrc $dst -Force
    } else {
        Invoke-WebRequest -Uri "$BossRepo/$src" -OutFile $dst -UseBasicParsing
    }
}

# Check Claude Code installed
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Err "Claude Code is not installed."
    Write-Err "Install from: https://claude.ai/code"
    exit 1
}

# Check python3 available
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Err "python3 is required but not found."
    Write-Err "Install Python 3 and try again."
    exit 1
}

Write-Log ""
Write-Log "BOSS -- Claude Code Enforcement Stack v$BossVersion"
Write-Log "============================================="
Write-Log ""
Write-Log "Detected: Windows"

# Detect project type
$cwd = Get-Location | Select-Object -ExpandProperty Path
$projectType = "generic"

if ((Test-Path (Join-Path $cwd "pyproject.toml")) -or
    (Test-Path (Join-Path $cwd "setup.py")) -or
    (Test-Path (Join-Path $cwd "pytest.ini"))) {
    $projectType = "python-backend"
} elseif (Test-Path (Join-Path $cwd "package.json")) {
    if ((Test-Path (Join-Path $cwd "playwright.config.ts")) -or
        (Test-Path (Join-Path $cwd "playwright.config.js"))) {
        $projectType = "fullstack"
    } else {
        $projectType = "node-api"
    }
} elseif (Test-Path (Join-Path $cwd "go.mod")) {
    $projectType = "go-service"
} elseif (Test-Path (Join-Path $cwd "Cargo.toml")) {
    $projectType = "rust-crate"
}

Write-Log "Detected: $projectType project"

if ($DryRun) {
    Write-Log "DRY RUN -- no changes will be made"
    Write-Log "Would install to: $BossDir"
    exit 0
}

# Create directories
Write-Log "Installing BOSS hooks..."
New-Item -ItemType Directory -Path (Join-Path $BossDir "hooks") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $BossDir "scripts") -Force | Out-Null

Copy-OrDownload "hooks/stop-gate.ps1" (Join-Path $BossDir "hooks\stop-gate.ps1")
Write-Log "  Copied stop-gate.ps1 to $BossDir\hooks\"

Copy-OrDownload "hooks/pre-build-gate.ps1" (Join-Path $BossDir "hooks\pre-build-gate.ps1")
Write-Log "  Copied pre-build-gate.ps1 to $BossDir\hooks\"

Copy-OrDownload "hooks/test-guard.ps1" (Join-Path $BossDir "hooks\test-guard.ps1")
Write-Log "  Copied test-guard.ps1 to $BossDir\hooks\"

Copy-OrDownload "hooks/auto-push.ps1" (Join-Path $BossDir "hooks\auto-push.ps1")
Write-Log "  Copied auto-push.ps1 to $BossDir\hooks\"

Copy-OrDownload "hooks/auto-pr.ps1" (Join-Path $BossDir "hooks\auto-pr.ps1")
Write-Log "  Copied auto-pr.ps1 to $BossDir\hooks\"

Copy-OrDownload "hooks/pre-push.ps1" (Join-Path $BossDir "hooks\pre-push.ps1")
Write-Log "  Copied pre-push.ps1 to $BossDir\hooks\"

Copy-OrDownload "scripts/patch-settings.py" (Join-Path $BossDir "scripts\patch-settings.py")

Write-Log ""
Write-Log "Patching settings.json..."

# REQ-087/088: detect WSL vs native Windows; use explicit PS path to avoid WSL routing
$runningInWSL = $false
try {
    if ($env:WSL_DISTRO_NAME -or $env:WSLENV) { $runningInWSL = $true }
    elseif ((Get-Process -Id $PID -ErrorAction SilentlyContinue).MainModule.FileName -match 'wsl') { $runningInWSL = $true }
} catch {}

if ($runningInWSL) {
    Write-Log "  Detected WSL -- using bash hooks"
    $stopGateCmd = "bash $BossDir/hooks/stop-gate.sh"
    $preGateCmd  = "bash $BossDir/hooks/pre-build-gate.sh"
    $testGuardCmd = "bash $BossDir/hooks/test-guard.sh"
} else {
    # Prefer PS7 (pwsh) for explicit path; fallback to PS5.1 system path
    $psExe = $null
    $pwshObj = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwshObj) {
        $psExe = $pwshObj.Source
    } else {
        $ps5 = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
        $psExe = if (Test-Path $ps5) { $ps5 } else { "powershell" }
    }
    $stopGateCmd  = "& `"$psExe`" -ExecutionPolicy Bypass -File `"$(Join-Path $BossDir 'hooks\stop-gate.ps1')`""
    $preGateCmd   = "& `"$psExe`" -ExecutionPolicy Bypass -File `"$(Join-Path $BossDir 'hooks\pre-build-gate.ps1')`""
    $testGuardCmd = "& `"$psExe`" -ExecutionPolicy Bypass -File `"$(Join-Path $BossDir 'hooks\test-guard.ps1')`""
    Write-Log "  Using PowerShell: $psExe"
}

& python (Join-Path $BossDir "scripts\patch-settings.py") --platform win `
    "--hook-command-ps1=$stopGateCmd" `
    "--pre-build-gate-ps1=$preGateCmd" `
    "--test-guard-ps1=$testGuardCmd"
Write-Log ""

# Template selection
if (-not $Template -and -not $Quiet) {
    Write-Log "Project template:"
    Write-Log "  1) Python backend (FastAPI/Django/Flask + pytest)"
    Write-Log "  2) Node API (Express/Fastify + Jest/Vitest)"
    Write-Log "  3) Full-stack (frontend + backend + Playwright)"
    Write-Log "  4) Go service"
    Write-Log "  5) Rust crate"
    Write-Log "  6) Generic (any language)"
    $choice = Read-Host "Choose [1-6] (default 6)"
    switch ($choice) {
        "1" { $Template = "python-backend" }
        "2" { $Template = "node-api" }
        "3" { $Template = "fullstack" }
        "4" { $Template = "go-service" }
        "5" { $Template = "rust-crate" }
        default { $Template = "generic" }
    }
}
if (-not $Template) { $Template = $projectType }

# FIX ISSUE-005: validate template against allowlist (prevent path traversal)
$validTemplates = @("python-backend", "node-api", "fullstack", "go-service", "rust-crate", "generic")
if ($validTemplates -notcontains $Template) {
    Write-Err "Unknown template: '$Template'. Valid: $($validTemplates -join ', ')"
    exit 1
}

# Copy CLAUDE.md template
$claudeMd = Join-Path $cwd "CLAUDE.md"
if (Test-Path $claudeMd) {
    if (Confirm-Action "CLAUDE.md already exists. Overwrite?") {
        Copy-OrDownload "templates/$Template.md" $claudeMd
        Write-Log "  Copied $Template template to .\CLAUDE.md"
    } else {
        Write-Log "  Skipped CLAUDE.md (kept existing)"
    }
} else {
    Copy-OrDownload "templates/$Template.md" $claudeMd
    Write-Log "  Copied $Template template to .\CLAUDE.md"
}

# GitHub Actions CI
if (-not $SkipCI) {
    if (Confirm-Action "Set up GitHub Actions CI?") {
        $workflowDir = Join-Path $cwd ".github\workflows"
        New-Item -ItemType Directory -Path $workflowDir -Force | Out-Null
        $ciFile = switch ($Template) {
            "python-backend" { "python" }
            "node-api"       { "node" }
            "fullstack"      { "node" }
            "go-service"     { "go" }
            "rust-crate"     { "rust" }
            "generic"        { "python" }
            default          { "python" }
        }
        Copy-OrDownload "ci-templates/$ciFile.yml" (Join-Path $workflowDir "test.yml")
        Write-Log "  Created .github\workflows\test.yml"
        if ($Template -eq "fullstack") {
            Copy-OrDownload "ci-templates/playwright.yml" (Join-Path $workflowDir "e2e.yml")
            Write-Log "  Created .github\workflows\e2e.yml"
        }
    }
}

# Install skills to ~/.claude/skills/ (Claude Code auto-discovers this path)
$skillsDir = Join-Path $HOME ".claude\skills"
foreach ($skill in @("build", "verify", "certify", "demo", "signoff", "run")) {
    $skillDst = Join-Path $skillsDir $skill
    New-Item -ItemType Directory -Path $skillDst -Force | Out-Null
    Copy-OrDownload "skills/$skill/SKILL.md" (Join-Path $skillDst "SKILL.md")
}
Write-Log "  Installed /build, /verify, /certify, /demo, /signoff, /run -> $skillsDir\"

# Install boss-delta.py to BossDir/scripts
New-Item -ItemType Directory -Path (Join-Path $BossDir "scripts") -Force | Out-Null
Copy-OrDownload "scripts/boss-delta.py" (Join-Path $BossDir "scripts\boss-delta.py")
Write-Log "  Installed boss-delta.py -> $BossDir\scripts\"

# Auto-install test runner dependencies
Write-Log ""
Write-Log "Checking test runner dependencies..."
$pythonOk = $false
if ($projectType -in @("python-backend", "generic")) {
    $pythonBin = $null
    foreach ($venv in @(".venv", "venv", "env")) {
        $candidate = Join-Path $cwd "$venv\Scripts\python.exe"
        if (Test-Path $candidate) { $pythonBin = $candidate; break }
    }
    if (-not $pythonBin) {
        $cmdObj = Get-Command python3 -ErrorAction SilentlyContinue
        if ($cmdObj) { $pythonBin = $cmdObj.Source }
    }
    if (-not $pythonBin) {
        $cmdObj = Get-Command python -ErrorAction SilentlyContinue
        if ($cmdObj) { $pythonBin = $cmdObj.Source }
    }
    if ($pythonBin) {
        $pytestCheck = & $pythonBin -m pytest --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log "  pytest not found -- installing..."
            $uvCmd = Get-Command uv -ErrorAction SilentlyContinue
            if ($uvCmd -and (Test-Path (Join-Path $cwd "pyproject.toml"))) {
                & uv add --dev pytest --quiet
                if ($LASTEXITCODE -eq 0) { Write-Log "  Installed pytest via uv" }
                else { Write-Err "Could not install pytest via uv -- run: pip install pytest" }
            } else {
                & $pythonBin -m pip install pytest --quiet
                if ($LASTEXITCODE -eq 0) { Write-Log "  Installed pytest via pip" }
                else { Write-Err "Could not install pytest -- run: pip install pytest" }
            }
        } else {
            Write-Log "  pytest: OK"
        }
        $pythonOk = $true
    } else {
        Write-Err "python not found -- install Python then run: pip install pytest"
    }
} elseif ($projectType -in @("node-api", "fullstack")) {
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    if ($nodeCmd) {
        Write-Log "  node: OK ($( & node --version ))"
        $pkgJson = Join-Path $cwd "package.json"
        if (Test-Path $pkgJson) {
            $pkg = Get-Content $pkgJson | ConvertFrom-Json
            if (-not $pkg.scripts -or -not $pkg.scripts.test) {
                Write-Log "  WARNING: no 'test' script in package.json -- stop hook will skip"
            }
        }
    } else {
        Write-Err "node not found -- install from https://nodejs.org"
    }
} elseif ($projectType -eq "go-service") {
    $goCmd = Get-Command go -ErrorAction SilentlyContinue
    if ($goCmd) { Write-Log "  go: OK ($( & go version ))" }
    else { Write-Err "go not found -- install from https://go.dev" }
} elseif ($projectType -eq "rust-crate") {
    $cargoCmd = Get-Command cargo -ErrorAction SilentlyContinue
    if ($cargoCmd) { Write-Log "  cargo: OK" }
    else { Write-Err "cargo not found -- install from https://rustup.rs" }
}

Write-Log ""
Write-Log "============================================="
Write-Log "BOSS installed."
Write-Log "Claude cannot exit while your tests are red."
Write-Log "============================================="
Write-Log ""
Write-Log "Next steps:"
Write-Log "  1. Edit CLAUDE.md with your product vision"
Write-Log "  2. Run: claude"
Write-Log "  3. Type your first requirement"
Write-Log "  4. Walk away"
Write-Log ""
Write-Log "Emergency bypass: set BOSS_SKIP=1 before running claude"
Write-Log ""
