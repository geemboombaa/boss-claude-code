# BOSS install.ps1 -- Windows installer
# Usage: iwr https://raw.githubusercontent.com/boss-claude/boss/main/install.ps1 | iex
# Or:    .\install.ps1 [-Quiet] [-Template python] [-SkipCI] [-DryRun]
param(
    [switch]$Quiet,
    [string]$Template = "",
    [switch]$SkipCI,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$BossVersion = "1.0.0"
$BossRepo = "https://raw.githubusercontent.com/boss-claude/boss/main"
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

Copy-OrDownload "scripts/patch-settings.py" (Join-Path $BossDir "scripts\patch-settings.py")

Write-Log ""
Write-Log "Patching settings.json..."
& python (Join-Path $BossDir "scripts\patch-settings.py") --platform win
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

# Install skills and scripts
foreach ($d in @("skills\build", "skills\verify", "skills\certify", "skills\demo", "skills\signoff", "scripts")) {
    New-Item -ItemType Directory -Path (Join-Path $BossDir $d) -Force | Out-Null
}
Copy-OrDownload "skills/build/SKILL.md"   (Join-Path $BossDir "skills\build\SKILL.md")
Copy-OrDownload "skills/verify/SKILL.md"  (Join-Path $BossDir "skills\verify\SKILL.md")
Copy-OrDownload "skills/certify/SKILL.md" (Join-Path $BossDir "skills\certify\SKILL.md")
Copy-OrDownload "skills/demo/SKILL.md"    (Join-Path $BossDir "skills\demo\SKILL.md")
Copy-OrDownload "skills/signoff/SKILL.md" (Join-Path $BossDir "skills\signoff\SKILL.md")
Copy-OrDownload "scripts/boss-delta.py"   (Join-Path $BossDir "scripts\boss-delta.py")
Write-Log "  Installed /build, /verify, /certify, /demo, /signoff skills"
Write-Log "  Installed boss-delta.py (smart delta)"

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
