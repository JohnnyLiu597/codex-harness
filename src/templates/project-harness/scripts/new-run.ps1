param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Status = "active",
    [string]$Summary = ""
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$slug = ($Name -replace '[^a-zA-Z0-9]+', '-').Trim('-').ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($slug)) {
    $slug = "run"
}

$runDir = Join-Path $root ("artifacts\runs\" + $stamp + "-" + $slug)
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$record = [ordered]@{
    schema = "harness-run-v1"
    name = $Name
    slug = $slug
    status = $Status
    created_at = (Get-Date).ToString("o")
    root = $root
    summary = $Summary
    files = @(
        "AGENTS.md",
        "mission.md",
        "CONTEXT.md",
        "MEMORY.md",
        "docs/architecture.md",
        "docs/commands.md",
        "docs/testing.md"
    )
}

$jsonPath = Join-Path $runDir "run.json"
$mdPath = Join-Path $runDir "summary.md"

$record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$md = @"
# Run: $Name

- Status: $Status
- Created: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
- Root: $root

## Summary

$Summary
"@

Set-Content -LiteralPath $mdPath -Value $md -Encoding UTF8

[ordered]@{
    status = "success"
    summary = "Created harness run folder."
    next_actions = @(
        "Fill summary.md with the current task state.",
        "Keep run artifacts lightweight unless the task is major."
    )
    artifacts = @($jsonPath, $mdPath)
} | ConvertTo-Json -Depth 5 -Compress
