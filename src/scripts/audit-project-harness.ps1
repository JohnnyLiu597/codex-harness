param(
    [string]$ProjectRoot = ".",
    [switch]$WriteReport
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$checks = New-Object System.Collections.Generic.List[object]

function Add-Check {
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

function Test-File {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    Test-Path -LiteralPath (Join-Path $root $RelativePath) -PathType Leaf
}

function Test-Directory {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    Test-Path -LiteralPath (Join-Path $root $RelativePath) -PathType Container
}

$requiredFiles = @(
    "AGENTS.md",
    "mission.md",
    "CONTEXT.md",
    "MEMORY.md",
    "docs\project.md",
    "docs\architecture.md",
    "docs\code-map.md",
    "docs\commands.md",
    "docs\testing.md",
    "docs\smoke.md",
    "docs\features.json",
    "docs\quality.md",
    "docs\reliability.md",
    "docs\security.md",
    "docs\tech-debt.md",
    "docs\observability.md",
    "docs\auth.md",
    "docs\profiles.md",
    "docs\retention.md",
    "docs\context.md",
    "docs\tool-surface.md",
    "docs\runtime.md",
    "docs\verification-gate.md",
    "docs\trace-evals.md",
    "docs\tool-failures.md",
    "docs\skill-surface.md",
    "harness.capabilities.json",
    "evals\prompts.csv",
    "evals\tool-evals\README.md",
    "scripts\verify-harness.ps1",
    "scripts\check-all.ps1",
    "scripts\check-features.ps1",
    "scripts\check-architecture.ps1",
    "scripts\check-tool-evals.ps1",
    "scripts\new-goal.ps1",
    "scripts\new-harness-change.ps1",
    "scripts\new-trace-eval.ps1",
    "scripts\new-session-summary.ps1",
    "scripts\new-agent-run.ps1",
    "scripts\new-learning-intake.ps1",
    "scripts\new-runtime-run.ps1",
    "scripts\invoke-verification-gate.ps1",
    "scripts\summarize-trace-evals.ps1",
    "scripts\new-tool-failure.ps1",
    "scripts\audit-skill-surface.ps1",
    "scripts\new-review.ps1",
    "scripts\new-run.ps1",
    "scripts\new-smoke-run.ps1",
    "scripts\safe-remove.ps1"
)

$missing = @($requiredFiles | Where-Object { -not (Test-File -RelativePath $_) })
if ($missing.Count -gt 0) {
    Add-Check -Name "required-files" -Status "warning" -Detail "Missing: $($missing -join ', ')"
} else {
    Add-Check -Name "required-files" -Status "passed" -Detail "All required harness files exist."
}

foreach ($dir in @(
    "artifacts\goals",
    "artifacts\harness-changes",
    "artifacts\runs",
    "artifacts\checks",
    "artifacts\tool-eval-checks",
    "artifacts\smoke-runs",
    "artifacts\reviews",
    "artifacts\session-summaries",
    "artifacts\agent-runs",
    "artifacts\learning-inbox",
    "artifacts\runtime-runs",
    "artifacts\verification-gates",
    "artifacts\tool-failures",
    "artifacts\trace-eval-summaries",
    "artifacts\skill-surface",
    "evals\tool-evals\cases"
)) {
    if (Test-Directory -RelativePath $dir) {
        Add-Check -Name "dir:$dir" -Status "passed" -Detail "exists"
    } else {
        Add-Check -Name "dir:$dir" -Status "warning" -Detail "missing"
    }
}

$featureFile = Join-Path $root "docs\features.json"
if (Test-Path -LiteralPath $featureFile) {
    try {
        Get-Content -LiteralPath $featureFile -Raw | ConvertFrom-Json | Out-Null
        Add-Check -Name "features-json" -Status "passed" -Detail "parseable"
    } catch {
        Add-Check -Name "features-json" -Status "failed" -Detail $_.Exception.Message
    }
}

$capabilityFile = Join-Path $root "harness.capabilities.json"
if (Test-Path -LiteralPath $capabilityFile) {
    try {
        Get-Content -LiteralPath $capabilityFile -Raw | ConvertFrom-Json | Out-Null
        Add-Check -Name "capability-manifest" -Status "passed" -Detail "parseable"
    } catch {
        Add-Check -Name "capability-manifest" -Status "failed" -Detail $_.Exception.Message
    }
}

$verifyScript = Join-Path $root "scripts\verify-harness.ps1"
if (Test-Path -LiteralPath $verifyScript) {
    Add-Check -Name "verify-command" -Status "info" -Detail "Run scripts\verify-harness.ps1 for project-local validation."
} else {
    Add-Check -Name "verify-command" -Status "warning" -Detail "No scripts\verify-harness.ps1 found."
}

$failed = @($checks | Where-Object { $_.status -eq "failed" })
$warnings = @($checks | Where-Object { $_.status -eq "warning" })
$status = if ($failed.Count -gt 0) { "failed" } elseif ($warnings.Count -gt 0) { "warning" } else { "passed" }

$record = [ordered]@{
    schema = "codex-project-harness-audit-v1"
    status = $status
    created_at = (Get-Date).ToString("o")
    project_root = $root
    checks = $checks.ToArray()
}

if ($WriteReport) {
    $runDir = Join-Path $root ("artifacts\checks\harness-audit-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null
    $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runDir "audit.json") -Encoding UTF8
}

$record | ConvertTo-Json -Depth 8 -Compress
