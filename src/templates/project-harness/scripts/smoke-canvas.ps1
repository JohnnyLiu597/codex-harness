param(
    [int]$Port = 5173,
    [switch]$KeepServer,
    [string]$Baseline = ""
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runDir = Join-Path $root ("artifacts\smoke-runs\" + $stamp + "-app-shell")
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$jsonPath = Join-Path $runDir "smoke.json"
$summaryPath = Join-Path $runDir "summary.md"

$status = "skipped"
$summary = "No project-specific app shell smoke is configured yet. Replace this script or route it to the repo's real smoke command."
if (Test-Path -LiteralPath (Join-Path $root "package.json")) {
    $summary = "package.json exists; add a project-specific browser or HTTP smoke before relying on runtime evidence."
}

[ordered]@{
    schema = "app-shell-smoke-v1"
    status = $status
    created_at = (Get-Date).ToString("o")
    root = $root
    port = $Port
    baseline = $Baseline
    summary = $summary
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$md = @"
# App Shell Smoke

- Status: $status
- Root: $root

## Summary

$summary
"@
Set-Content -LiteralPath $summaryPath -Value $md -Encoding UTF8

[ordered]@{
    status = "success"
    summary = "App shell smoke recorded as skipped until project-specific runtime smoke is configured."
    smoke_status = $status
    artifacts = @($jsonPath, $summaryPath)
} | ConvertTo-Json -Depth 5 -Compress
