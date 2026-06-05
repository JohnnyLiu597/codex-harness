param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Status = "active",
    [string]$Baseline = "",
    [string]$Summary = "",
    [string[]]$Checks = @(),
    [string[]]$Evidence = @()
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$slug = ($Name -replace '[^a-zA-Z0-9]+', '-').Trim('-').ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($slug)) {
    $slug = "smoke"
}

$runDir = Join-Path $root ("artifacts\smoke-runs\" + $stamp + "-" + $slug)
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$record = [ordered]@{
    schema = "smoke-run-v1"
    name = $Name
    slug = $slug
    status = $Status
    baseline = $Baseline
    created_at = (Get-Date).ToString("o")
    root = $root
    summary = $Summary
    checks = $Checks
    evidence = $Evidence
}

$jsonPath = Join-Path $runDir "smoke.json"
$mdPath = Join-Path $runDir "summary.md"

$record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$checkLines = if ($Checks.Count -gt 0) {
    ($Checks | ForEach-Object { "- $_" }) -join "`r`n"
} else {
    "- Not recorded yet."
}

$evidenceLines = if ($Evidence.Count -gt 0) {
    ($Evidence | ForEach-Object { "- $_" }) -join "`r`n"
} else {
    "- Not recorded yet."
}

$md = @"
# Smoke Run: $Name

- Status: $Status
- Created: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
- Baseline: $Baseline
- Root: $root

## Summary

$Summary

## Checks

$checkLines

## Evidence

$evidenceLines
"@

Set-Content -LiteralPath $mdPath -Value $md -Encoding UTF8

[ordered]@{
    status = "success"
    summary = "Created smoke run folder."
    artifacts = @($jsonPath, $mdPath)
} | ConvertTo-Json -Depth 5 -Compress
