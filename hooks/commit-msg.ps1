# BOSS commit-msg.ps1 -- enforces conventional commits (Windows)
param([string]$MsgFile)

$msg = Get-Content $MsgFile -Raw
$pattern = '^(feat|fix|docs|test|refactor|chore|ci|perf|style|build|revert)(\(.+\))?: .{1,72}'

if ($msg -notmatch $pattern) {
    [Console]::Error.WriteLine("BOSS commit-msg: message must follow conventional commits")
    [Console]::Error.WriteLine("  Pattern: type(scope): description")
    [Console]::Error.WriteLine("  Types:   feat|fix|docs|test|refactor|chore|ci|perf|style|build|revert")
    [Console]::Error.WriteLine("  Example: feat(hooks): add stop-gate language detection")
    [Console]::Error.WriteLine("  Your message: $msg")
    exit 1
}

exit 0
