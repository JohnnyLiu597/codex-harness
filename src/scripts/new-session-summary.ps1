param(
    [string]$ProjectRoot = ".",
    [string]$Name = "session-summary",
    [string]$Status = "in-progress",
    [string]$Objective = "",
    [string[]]$Completed = @(),
    [string[]]$Decisions = @(),
    [string[]]$OpenQuestions = @(),
    [string[]]$NextActions = @(),
    [string[]]$Files = @(),
    [string[]]$Checks = @(),
    [switch]$SetCurrent
)

$ErrorActionPreference = "Stop"

function ConvertTo-Slug {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "session-summary" }
    $slug = ($Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) { return "session-summary" }
    return $slug
}

function Format-List {
    param([string[]]$Items)
    if ($Items.Count -eq 0) { return "- Not recorded." }
    return (($Items | ForEach-Object { "- $_" }) -join "`r`n")
}

if ($ProjectRoot -eq ".") {
    $scriptProjectRoot = Join-Path $PSScriptRoot ".."
    if ((Test-Path -LiteralPath (Join-Path $scriptProjectRoot "mission.md")) -and
        (Test-Path -LiteralPath (Join-Path $scriptProjectRoot "CONTEXT.md"))) {
        $ProjectRoot = $scriptProjectRoot
    }
}
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$id = "$stamp-$(ConvertTo-Slug -Value $Name)"
$runDir = Join-Path $root ("artifacts\session-summaries\" + $id)
$jsonPath = Join-Path $runDir "session.json"
$summaryPath = Join-Path $runDir "summary.md"

New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$record = [ordered]@{
    schema = "codex-session-summary-v1"
    id = $id
    created_at = (Get-Date).ToString("o")
    project_root = $root
    name = $Name
    status = $Status
    objective = $Objective
    completed = $Completed
    decisions = $Decisions
    open_questions = $OpenQuestions
    next_actions = $NextActions
    files = $Files
    checks = $Checks
}

$record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$md = @"
# Session Summary

- ID: $id
- Status: $Status
- Created: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
- Project: $root

## Objective

$Objective

## Completed

$(Format-List -Items $Completed)

## Decisions

$(Format-List -Items $Decisions)

## Open Questions

$(Format-List -Items $OpenQuestions)

## Next Actions

$(Format-List -Items $NextActions)

## Files

$(Format-List -Items $Files)

## Checks

$(Format-List -Items $Checks)
"@

Set-Content -LiteralPath $summaryPath -Value $md -Encoding UTF8

$currentPath = $null
if ($SetCurrent) {
    $currentPath = Join-Path $root "artifacts\session-summaries\current.md"
    Set-Content -LiteralPath $currentPath -Value $md -Encoding UTF8
}

[ordered]@{
    status = "success"
    summary = "Session summary created."
    id = $id
    artifacts = @($jsonPath, $summaryPath)
    current = $currentPath
} | ConvertTo-Json -Depth 5 -Compress
