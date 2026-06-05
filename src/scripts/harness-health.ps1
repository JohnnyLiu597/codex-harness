param(
    [string]$CodexHome = "$env:USERPROFILE\.codex",
    [string]$ProjectRoot = "",
    [switch]$SkipEvals
)

$ErrorActionPreference = "Stop"

$codexHomePath = (Resolve-Path -LiteralPath $CodexHome).Path
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$healthRoot = Join-Path $codexHomePath "harness-health"
$runDir = Join-Path $healthRoot $stamp
$jsonPath = Join-Path $runDir "health.json"
$summaryPath = Join-Path $runDir "summary.md"
$checks = New-Object System.Collections.Generic.List[object]

New-Item -ItemType Directory -Force -Path $runDir | Out-Null

function Add-HealthCheck {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Status,
        [string]$Detail = ""
    )
    $checks.Add([pscustomobject]@{
        name = $Name
        status = $Status
        detail = $Detail
    }) | Out-Null
}

function Get-McpServerNames {
    param([Parameter(Mandatory = $true)][string]$Config)

    @([regex]::Matches($Config, '(?m)^\[mcp_servers\.([^\.\]]+)(?:\.[^\]]+)?\]') |
        ForEach-Object { $_.Groups[1].Value } |
        Sort-Object -Unique)
}

function Get-McpSubsections {
    param([Parameter(Mandatory = $true)][string]$Config)

    @([regex]::Matches($Config, '(?m)^\[mcp_servers\.([^\.\]]+)\.([^\]]+)\]') |
        ForEach-Object { "$($_.Groups[1].Value).$($_.Groups[2].Value)" } |
        Sort-Object -Unique)
}

try {
    $globalVerifyRaw = & (Join-Path $codexHomePath "scripts\verify-global-harness.ps1") -CodexHome $codexHomePath
    Add-HealthCheck -Name "global-harness" -Status "passed" -Detail "verify-global-harness.ps1 passed."
} catch {
    Add-HealthCheck -Name "global-harness" -Status "failed" -Detail $_.Exception.Message
}

$config = Get-Content -LiteralPath (Join-Path $codexHomePath "config.toml") -Raw
$mcpNames = Get-McpServerNames -Config $config
$mcpSubsections = Get-McpSubsections -Config $config
Add-HealthCheck -Name "mcp-surface" -Status "info" -Detail "servers: $($mcpNames -join ', ')"
if ($mcpSubsections.Count -gt 0) {
    Add-HealthCheck -Name "mcp-subsections" -Status "info" -Detail "subsections: $($mcpSubsections -join ', ')"
}

$activeSkillDirs = @()
if (Test-Path -LiteralPath (Join-Path $codexHomePath "skills")) {
    $activeSkillDirs = @(Get-ChildItem -LiteralPath (Join-Path $codexHomePath "skills") -Directory -ErrorAction SilentlyContinue)
}
Add-HealthCheck -Name "active-skills" -Status "info" -Detail "$($activeSkillDirs.Count) active skill directories."

try {
    $surfaceRaw = & (Join-Path $codexHomePath "scripts\check-harness-surface.ps1") -CodexHome $codexHomePath
    $surface = $surfaceRaw | ConvertFrom-Json
    $surfaceDetails = @($surface.checks | ForEach-Object { "$($_.name):$($_.status)" }) -join ", "
    Add-HealthCheck -Name "harness-surface" -Status $surface.status -Detail $surfaceDetails
} catch {
    Add-HealthCheck -Name "harness-surface" -Status "failed" -Detail $_.Exception.Message
}

if (Test-Path -LiteralPath (Join-Path $codexHomePath "hook-logs\latest-stop.txt")) {
    Add-HealthCheck -Name "stop-hook-log" -Status "passed" -Detail "latest-stop.txt exists."
} else {
    Add-HealthCheck -Name "stop-hook-log" -Status "warning" -Detail "No Stop hook log yet."
}

if (-not $SkipEvals) {
    try {
        $evalRaw = & (Join-Path $codexHomePath "harness-evals\run-harness-evals.ps1") -CodexHome $codexHomePath
        Add-HealthCheck -Name "harness-evals" -Status "passed" -Detail "run-harness-evals.ps1 passed."
    } catch {
        Add-HealthCheck -Name "harness-evals" -Status "failed" -Detail $_.Exception.Message
    }
}

if (-not [string]::IsNullOrWhiteSpace($ProjectRoot) -and (Test-Path -LiteralPath $ProjectRoot)) {
    $projectVerify = Join-Path $ProjectRoot "scripts\verify-harness.ps1"
    if (Test-Path -LiteralPath $projectVerify) {
        try {
            & $projectVerify | Out-Null
            Add-HealthCheck -Name "project-harness" -Status "passed" -Detail $ProjectRoot
        } catch {
            Add-HealthCheck -Name "project-harness" -Status "failed" -Detail $_.Exception.Message
        }
    } else {
        Add-HealthCheck -Name "project-harness" -Status "warning" -Detail "No scripts\verify-harness.ps1 at $ProjectRoot."
    }
}

$failed = @($checks | Where-Object { $_.status -eq "failed" })
$warnings = @($checks | Where-Object { $_.status -eq "warning" })
$status = if ($failed.Count -gt 0) { "failed" } elseif ($warnings.Count -gt 0) { "warning" } else { "passed" }

$record = [pscustomobject]@{
    schema = "codex-harness-health-v1"
    status = $status
    created_at = (Get-Date).ToString("o")
    codex_home = $codexHomePath
    project_root = $ProjectRoot
    checks = $checks.ToArray()
    artifacts = @($jsonPath, $summaryPath)
}

$record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$checkLines = if ($checks.Count -gt 0) {
    ($checks | ForEach-Object { "- $($_.status): $($_.name) $($_.detail)" }) -join "`r`n"
} else {
    "- No checks recorded."
}

$md = @"
# Codex Harness Health

- Status: $status
- Created: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
- Codex home: $codexHomePath
- Project root: $ProjectRoot

## Checks

$checkLines

## Artifacts

- health.json
"@

Set-Content -LiteralPath $summaryPath -Value $md -Encoding UTF8

[ordered]@{
    status = $status
    summary = "Codex harness health completed."
    artifacts = @($jsonPath, $summaryPath)
} | ConvertTo-Json -Depth 5 -Compress
