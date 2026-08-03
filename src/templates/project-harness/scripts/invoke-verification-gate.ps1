param(
    [string]$ProjectRoot = ".",
    [ValidateSet("DocsOnly", "HarnessOnly", "Runtime", "Full", "BeforeCommit")]
    [string]$Mode = "HarnessOnly",
    [switch]$DocsOnly,
    [switch]$HarnessOnly,
    [switch]$Runtime,
    [switch]$Full,
    [switch]$BeforeCommit,
    [switch]$ContinueOnError,
    [switch]$SkipLint,
    [switch]$SkipBuild,
    [switch]$SkipCargo,
    [string]$BaseRef = "HEAD~1"
)

$ErrorActionPreference = "Stop"

if ($DocsOnly) { $Mode = "DocsOnly" }
if ($HarnessOnly) { $Mode = "HarnessOnly" }
if ($Runtime) { $Mode = "Runtime" }
if ($Full) { $Mode = "Full" }
if ($BeforeCommit) { $Mode = "BeforeCommit" }

if ($ProjectRoot -eq ".") {
    $scriptProjectRoot = Join-Path $PSScriptRoot ".."
    if ((Test-Path -LiteralPath (Join-Path $scriptProjectRoot "mission.md")) -and
        (Test-Path -LiteralPath (Join-Path $scriptProjectRoot "CONTEXT.md"))) {
        $ProjectRoot = $scriptProjectRoot
    }
}

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$safeMode = $Mode.ToLowerInvariant()
$runDir = Join-Path $root ("artifacts\verification-gates\" + $stamp + "-" + $safeMode)
$jsonPath = Join-Path $runDir "verification-gate.json"
$summaryPath = Join-Path $runDir "summary.md"
$steps = New-Object System.Collections.Generic.List[object]

New-Item -ItemType Directory -Force -Path $runDir | Out-Null

function Resolve-ProjectScript {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [switch]$GlobalFallback
    )

    $projectScript = Join-Path $root "scripts\$Name"
    if (Test-Path -LiteralPath $projectScript) { return $projectScript }

    if ($GlobalFallback) {
        $globalScript = Join-Path "$env:USERPROFILE\.codex\scripts" $Name
        if (Test-Path -LiteralPath $globalScript) { return $globalScript }
    }

    return ""
}

function Get-StepStatusFromOutput {
    param(
        [string]$Output,
        [string]$DefaultStatus = "passed"
    )

    if ([string]::IsNullOrWhiteSpace($Output)) { return $DefaultStatus }
    try {
        $json = $Output | ConvertFrom-Json
        if ($json.status -in @("failed", "failure", "error")) { return "failed" }
        if ($json.status -eq "warning") { return "warning" }
        return $DefaultStatus
    } catch {
        return $DefaultStatus
    }
}

function Invoke-GateStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Script,
        [switch]$Optional
    )

    $safeName = ($Name -replace '[^a-zA-Z0-9]+', '-').Trim('-').ToLowerInvariant()
    $logPath = Join-Path $runDir "$safeName.log"
    $started = Get-Date
    $status = "passed"
    $message = ""

    try {
        Push-Location $root
        try {
            $output = & $Script 2>&1
            $message = ($output | Out-String).Trim()
            $status = Get-StepStatusFromOutput -Output $message
        } finally {
            Pop-Location
        }
    } catch {
        $status = if ($Optional) { "skipped" } else { "failed" }
        $message = $_.Exception.Message
    }

    Set-Content -LiteralPath $logPath -Value $message -Encoding UTF8
    $durationMs = [int]((Get-Date) - $started).TotalMilliseconds
    $steps.Add([pscustomobject]@{
        name = $Name
        status = $status
        duration_ms = $durationMs
        log = $logPath
        optional = [bool]$Optional
    }) | Out-Null

    if ($status -eq "failed" -and -not $ContinueOnError) {
        throw "Verification gate failed at $Name. See $logPath"
    }
}

function Invoke-ScriptIfPresent {
    param(
        [Parameter(Mandatory = $true)][string]$StepName,
        [Parameter(Mandatory = $true)][string]$ScriptName,
        [hashtable]$Parameters = @{},
        [switch]$GlobalFallback,
        [switch]$Optional
    )

    $scriptPath = Resolve-ProjectScript -Name $ScriptName -GlobalFallback:$GlobalFallback
    if (-not $scriptPath) {
        $safeName = ($StepName -replace '[^a-zA-Z0-9]+', '-').Trim('-').ToLowerInvariant()
        $logPath = Join-Path $runDir "$safeName.log"
        Set-Content -LiteralPath $logPath -Value "Script not found: $ScriptName" -Encoding UTF8
        $steps.Add([pscustomobject]@{
            name = $StepName
            status = "skipped"
            duration_ms = 0
            log = $logPath
            optional = $true
        }) | Out-Null
        return
    }

    Invoke-GateStep -Name $StepName -Optional:$Optional -Script {
        & $scriptPath @Parameters
    }
}

function Invoke-DocsGate {
    $projectDocsScript = Join-Path $root "scripts\check-project-docs.ps1"
    if (Test-Path -LiteralPath $projectDocsScript) {
        Invoke-GateStep -Name "docs-sync" -Script { & $projectDocsScript -BaseRef $BaseRef }
    } else {
        Invoke-ScriptIfPresent -StepName "docs-sync" -ScriptName "check-project-docs.ps1" -Parameters @{ ProjectRoot = $root; BaseRef = $BaseRef } -GlobalFallback
    }
    Invoke-ScriptIfPresent -StepName "feature-list" -ScriptName "check-features.ps1"
    Invoke-ScriptIfPresent -StepName "architecture-check" -ScriptName "check-architecture.ps1" -Optional
}

function Invoke-HarnessGate {
    Invoke-ScriptIfPresent -StepName "harness-verify" -ScriptName "verify-harness.ps1"
    Invoke-ScriptIfPresent -StepName "project-harness-audit" -ScriptName "audit-project-harness.ps1" -GlobalFallback
    Invoke-ScriptIfPresent -StepName "context-budget-audit" -ScriptName "audit-context-budget.ps1"
    Invoke-ScriptIfPresent -StepName "component-registry-audit" -ScriptName "audit-harness-components.ps1"
    Invoke-ScriptIfPresent -StepName "feature-list" -ScriptName "check-features.ps1"
    Invoke-ScriptIfPresent -StepName "tool-evals" -ScriptName "check-tool-evals.ps1"
    Invoke-ScriptIfPresent -StepName "architecture-check" -ScriptName "check-architecture.ps1" -Optional
    Invoke-ScriptIfPresent -StepName "trace-evals-dry-run" -ScriptName "run-codex-trace-evals.ps1" -Parameters @{ DryRun = $true } -Optional
}

try {
    switch ($Mode) {
        "DocsOnly" {
            Invoke-DocsGate
        }
        "HarnessOnly" {
            Invoke-HarnessGate
        }
        "Runtime" {
            $parameters = @{ Runtime = $true; Smoke = $true; TraceEvals = $true }
            if ($SkipLint) { $parameters.SkipLint = $true }
            if ($SkipBuild) { $parameters.SkipBuild = $true }
            if ($SkipCargo) { $parameters.SkipCargo = $true }
            if ($ContinueOnError) { $parameters.ContinueOnError = $true }
            Invoke-ScriptIfPresent -StepName "check-all-runtime" -ScriptName "check-all.ps1" -Parameters $parameters
        }
        "Full" {
            $parameters = @{ Full = $true }
            if ($SkipLint) { $parameters.SkipLint = $true }
            if ($SkipBuild) { $parameters.SkipBuild = $true }
            if ($SkipCargo) { $parameters.SkipCargo = $true }
            if ($ContinueOnError) { $parameters.ContinueOnError = $true }
            Invoke-ScriptIfPresent -StepName "check-all-full" -ScriptName "check-all.ps1" -Parameters $parameters
        }
        "BeforeCommit" {
            Invoke-DocsGate
            Invoke-HarnessGate
        }
    }
} finally {
    $failed = @($steps | Where-Object { $_.status -eq "failed" })
    $warnings = @($steps | Where-Object { $_.status -eq "warning" })
    $status = if ($failed.Count -gt 0) { "failed" } elseif ($warnings.Count -gt 0) { "warning" } else { "passed" }

    $record = [ordered]@{
        schema = "codex-verification-gate-v1"
        status = $status
        mode = $Mode
        created_at = (Get-Date).ToString("o")
        root = $root
        continue_on_error = [bool]$ContinueOnError
        steps = $steps.ToArray()
    }
    $record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    $stepLines = if ($steps.Count -gt 0) {
        ($steps | ForEach-Object { "- $($_.status): $($_.name) ($($_.duration_ms) ms)" }) -join "`r`n"
    } else {
        "- No steps ran."
    }

    $md = @"
# Verification Gate

- Status: $status
- Mode: $Mode
- Created: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
- Project: $root

## Steps

$stepLines

## Artifacts

- verification-gate.json
- step logs in this folder
"@

    Set-Content -LiteralPath $summaryPath -Value $md -Encoding UTF8
}

[ordered]@{
    status = if (@($steps | Where-Object { $_.status -eq "failed" }).Count -gt 0) { "failed" } elseif (@($steps | Where-Object { $_.status -eq "warning" }).Count -gt 0) { "warning" } else { "success" }
    summary = "Verification gate completed."
    mode = $Mode
    artifacts = @($jsonPath, $summaryPath)
} | ConvertTo-Json -Depth 5 -Compress
