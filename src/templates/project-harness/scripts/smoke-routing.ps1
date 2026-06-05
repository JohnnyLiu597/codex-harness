param(
    [switch]$Runtime,
    [string[]]$RequiredPath = @(),
    [string]$Summary = ""
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runDir = Join-Path $root ("artifacts\smoke-runs\" + $stamp + "-routing")
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$jsonPath = Join-Path $runDir "smoke.json"
$summaryPath = Join-Path $runDir "summary.md"

if ($RequiredPath.Count -eq 0) { $RequiredPath = @("docs\architecture.md", "docs\code-map.md", "docs\features.json") }
$missing = @($RequiredPath | Where-Object { -not (Test-Path -LiteralPath (Join-Path $root $_)) })
$status = if ($missing.Count -gt 0) { "failed" } elseif ($Runtime) { "blocked-runtime-not-implemented" } else { "passed-static" }
$notes = @()
if ($Runtime) { $notes += "Runtime route smoke is project-specific; add command/UI evidence for this repo." }
if ($Summary) { $notes += $Summary }

[ordered]@{ schema = "routing-smoke-v1"; status = $status; created_at = (Get-Date).ToString("o"); runtime = [bool]$Runtime; required = $RequiredPath; missing = $missing; notes = $notes } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$missingLines = if ($missing.Count -gt 0) { ($missing | ForEach-Object { "- $_" }) -join "`r`n" } else { "- None." }
$noteLines = if ($notes.Count -gt 0) { ($notes | ForEach-Object { "- $_" }) -join "`r`n" } else { "- Static routing anchors exist." }
$md = @"
# Routing Smoke

- Status: $status
- Runtime requested: $([bool]$Runtime)

## Missing

$missingLines

## Notes

$noteLines
"@
Set-Content -LiteralPath $summaryPath -Value $md -Encoding UTF8
if ($status -eq "failed") { throw "Routing smoke failed. See $summaryPath" }
[ordered]@{ status = "success"; summary = "Routing smoke completed."; smoke_status = $status; artifacts = @($jsonPath, $summaryPath) } | ConvertTo-Json -Depth 5 -Compress
