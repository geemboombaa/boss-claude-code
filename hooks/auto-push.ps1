# auto-push.ps1 — PostToolUse hook: auto-push after git commit
# Fires after Bash tool calls containing 'git commit'
param()

$ErrorActionPreference = "SilentlyContinue"

# Read stdin payload (PostToolUse format)
$rawInput = ""
if ([Console]::IsInputRedirected) {
    try { $rawInput = [Console]::In.ReadToEnd() } catch {}
}

$payload = $null
if ($rawInput.Trim()) {
    try { $payload = $rawInput | ConvertFrom-Json } catch {}
}

# Only fire on Bash tool calls containing 'git commit'
$toolName = if ($payload) { $payload.tool_name } else { "" }
$toolInput = if ($payload) { $payload.tool_input } else { $null }
$command = if ($toolInput) { $toolInput.command } else { "" }

if ($toolName -ne "Bash" -or $command -notmatch "git\s+commit") {
    exit 0
}

# BOSS_SKIP bypass
if ($env:BOSS_SKIP -eq "1") {
    [Console]::Error.WriteLine("[BOSS auto-push] BOSS_SKIP=1 -- skipped")
    exit 0
}

# CWD from payload or current
$cwd = if ($payload -and $payload.cwd) { $payload.cwd } else { (Get-Location).Path }

# Derive branch slug from CLAUDE.md requirement section
$slug = "work"
$claudeMd = Join-Path $cwd "CLAUDE.md"
if (Test-Path $claudeMd) {
    $lines = Get-Content $claudeMd -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^[Rr]equirement[:\s]+(.+)$') {
            $slug = $Matches[1].Trim()
            break
        }
        if ($trimmed -and $trimmed -notmatch '^#' -and $trimmed.Length -gt 3) {
            $slug = $trimmed
            break
        }
    }
}

# Normalize slug
$slug = $slug.ToLower() -replace '[^a-z0-9\s-]', '' -replace '\s+', '-' -replace '-{2,}', '-'
$slug = $slug.Trim('-')
if ($slug.Length -gt 60) { $slug = $slug.Substring(0, 60).TrimEnd('-') }
if (-not $slug) { $slug = "work" }

# Branch prefix (BOSS_BRANCH_PREFIX overrides default)
$prefix = if ($env:BOSS_BRANCH_PREFIX) { $env:BOSS_BRANCH_PREFIX } else { "boss/" }
$branch = "$prefix$slug"

# Push with -u origin to create remote tracking branch
[Console]::Error.WriteLine("[BOSS auto-push] Pushing to origin/$branch ...")
Push-Location $cwd
try {
    $out = git push -u origin "HEAD:$branch" 2>&1
    if ($LASTEXITCODE -eq 0) {
        [Console]::Error.WriteLine("[BOSS auto-push] Pushed to $branch")
        # Trigger PR creation after push
        $autopr = Join-Path $HOME ".claude\boss\hooks\auto-pr.ps1"
        if (Test-Path $autopr) {
            & powershell -ExecutionPolicy Bypass -File $autopr -CwdOverride $cwd 2>&1 | ForEach-Object {
                [Console]::Error.WriteLine($_)
            }
        }
    } else {
        [Console]::Error.WriteLine("[BOSS auto-push] Push failed: $out")
    }
} finally {
    Pop-Location
}

exit 0
