param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Status = "completed",
    [string]$Reviewer = "codex",
    [string]$Summary = "",
    [string[]]$Findings = @(),
    [string[]]$Checks = @(),
    [string[]]$Evidence = @(),
    [string[]]$ResidualRisk = @()
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$slug = ($Name -replace '[^a-zA-Z0-9]+', '-').Trim('-').ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($slug)) {
    $slug = "review"
}

$runDir = Join-Path $root ("artifacts\reviews\" + $stamp + "-" + $slug)
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$jsonPath = Join-Path $runDir "review.json"
$summaryPath = Join-Path $runDir "summary.md"

$branch = ""
$head = ""
try {
    $branch = (git -C $root branch --show-current 2>$null | Out-String).Trim()
    $head = (git -C $root rev-parse --short HEAD 2>$null | Out-String).Trim()
} catch {
    $branch = "unknown"
    $head = "unknown"
}

$record = [ordered]@{
    schema = "codex-review-v1"
    name = $Name
    status = $Status
    reviewer = $Reviewer
    created_at = (Get-Date).ToString("o")
    root = $root
    branch = $branch
    head = $head
    summary = $Summary
    findings = $Findings
    checks = $Checks
    evidence = $Evidence
    residual_risk = $ResidualRisk
}
$record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

function Format-Lines {
    param([string[]]$Lines)
    if ($Lines.Count -eq 0) { return "- None." }
    return (($Lines | ForEach-Object { "- $_" }) -join "`r`n")
}

$md = @"
# Review: $Name

- Status: $Status
- Reviewer: $Reviewer
- Branch: $branch
- Head: $head
- Created: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))

## Summary

$Summary

## Findings

$(Format-Lines -Lines $Findings)

## Checks

$(Format-Lines -Lines $Checks)

## Evidence

$(Format-Lines -Lines $Evidence)

## Residual Risk

$(Format-Lines -Lines $ResidualRisk)
"@
Set-Content -LiteralPath $summaryPath -Value $md -Encoding UTF8

[ordered]@{
    status = "success"
    summary = "Created review record."
    artifacts = @($jsonPath, $summaryPath)
} | ConvertTo-Json -Depth 5 -Compress
