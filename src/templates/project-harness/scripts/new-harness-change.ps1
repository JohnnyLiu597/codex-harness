param(
    [Parameter(Mandatory = $true)][string]$Name,
    [ValidateSet("global", "project", "skill", "mcp", "hook", "eval", "smoke", "template", "script", "docs", "config")]
    [string]$Layer = "project",
    [ValidateSet("planned", "completed", "deferred", "blocked")]
    [string]$Status = "planned",
    [string]$Summary = "",
    [string[]]$Files = @(),
    [string[]]$Checks = @(),
    [string[]]$Evidence = @(),
    [string[]]$Assumptions = @(),
    [string]$Rollback = "",
    [string]$Root = ""
)

$ErrorActionPreference = "Stop"

function Test-HasNonEmptyItems {
    param([object]$Value)

    if ($null -eq $Value) { return $false }
    foreach ($item in @($Value)) {
        if ($null -ne $item -and -not [string]::IsNullOrWhiteSpace([string]$item)) {
            return $true
        }
    }
    return $false
}

if (-not $Root) {
    $Root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
} else {
    $Root = (Resolve-Path -LiteralPath $Root).Path
}

if ($Status -eq "completed" -and -not (Test-HasNonEmptyItems $Checks) -and -not (Test-HasNonEmptyItems $Evidence)) {
    throw "Completed harness changes must include at least one check or evidence entry."
}

$isGlobalHarness = (Test-Path -LiteralPath (Join-Path $Root "config.toml")) -and
    (Test-Path -LiteralPath (Join-Path $Root "templates\project-harness"))
$recordRoot = if ($isGlobalHarness) {
    Join-Path $Root "harness-changes"
} else {
    Join-Path $Root "artifacts\harness-changes"
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$safeName = ([regex]::Replace($Name.ToLowerInvariant(), '[^a-z0-9]+', '-')).Trim('-')
if (-not $safeName) { $safeName = "harness-change" }
$id = "$stamp-$safeName"
$runDir = Join-Path $recordRoot $id
$jsonPath = Join-Path $runDir "change.json"
$summaryPath = Join-Path $runDir "summary.md"

New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$record = [ordered]@{
    schema = "codex-harness-change-v1"
    id = $id
    name = $Name
    layer = $Layer
    status = $Status
    created_at = (Get-Date).ToString("o")
    root = $Root
    summary = $Summary
    assumptions = @($Assumptions)
    files = @($Files)
    checks = @($Checks)
    evidence = @($Evidence)
    rollback = $Rollback
}
$record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$assumptionLines = if ($Assumptions.Count -gt 0) { ($Assumptions | ForEach-Object { "- $_" }) -join "`r`n" } else { "- None recorded." }
$fileLines = if ($Files.Count -gt 0) { ($Files | ForEach-Object { "- $_" }) -join "`r`n" } else { "- None recorded." }
$checkLines = if ($Checks.Count -gt 0) { ($Checks | ForEach-Object { "- $_" }) -join "`r`n" } else { "- None recorded." }
$evidenceLines = if ($Evidence.Count -gt 0) { ($Evidence | ForEach-Object { "- $_" }) -join "`r`n" } else { "- None recorded." }
$rollbackText = if ([string]::IsNullOrWhiteSpace($Rollback)) { "Not recorded." } else { $Rollback }

$md = @"
# Harness Change

- ID: $id
- Name: $Name
- Layer: $Layer
- Status: $Status
- Created: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
- Root: $Root

## Summary

$Summary

## Assumptions

$assumptionLines

## Files

$fileLines

## Checks

$checkLines

## Evidence

$evidenceLines

## Rollback

$rollbackText
"@

Set-Content -LiteralPath $summaryPath -Value $md -Encoding UTF8

[ordered]@{
    status = "success"
    summary = "Harness change record created."
    id = $id
    artifacts = @($jsonPath, $summaryPath)
} | ConvertTo-Json -Depth 5 -Compress
