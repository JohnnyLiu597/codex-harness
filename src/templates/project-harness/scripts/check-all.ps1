param(
    [switch]$Full,
    [switch]$Runtime,
    [switch]$Smoke,
    [switch]$TraceEvals,
    [switch]$RealTraceEvals,
    [switch]$SkipLint,
    [switch]$SkipBuild,
    [switch]$SkipCargo,
    [switch]$ContinueOnError
)

$ErrorActionPreference = "Stop"

if ($Full) {
    $Runtime = $true
    $Smoke = $true
    $TraceEvals = $true
}
if ($RealTraceEvals) {
    $TraceEvals = $true
}

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runDir = Join-Path $root ("artifacts\checks\" + $stamp + "-check-all")
$jsonPath = Join-Path $runDir "check-all.json"
$summaryPath = Join-Path $runDir "summary.md"
$steps = New-Object System.Collections.Generic.List[object]

New-Item -ItemType Directory -Force -Path $runDir | Out-Null

function Invoke-CheckStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Script
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
        } finally {
            Pop-Location
        }
    } catch {
        $status = "failed"
        $message = $_.Exception.Message
    }

    Set-Content -LiteralPath $logPath -Value $message -Encoding UTF8
    $durationMs = [int]((Get-Date) - $started).TotalMilliseconds
    $step = [ordered]@{
        name = $Name
        status = $status
        duration_ms = $durationMs
        log = $logPath
    }
    $steps.Add($step) | Out-Null

    if ($status -eq "failed" -and -not $ContinueOnError) {
        throw "Check failed: $Name. See $logPath"
    }
}

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$File,
        [string[]]$Args = @(),
        [string]$WorkingDirectory = $root
    )

    Push-Location $WorkingDirectory
    try {
        & $File @Args
        $exitCode = $LASTEXITCODE
        if ($null -ne $exitCode -and $exitCode -ne 0) {
            throw "$File $($Args -join ' ') failed with exit code $exitCode"
        }
    } finally {
        Pop-Location
    }
}

try {
    Invoke-CheckStep -Name "harness-verify" -Script { & .\scripts\verify-harness.ps1 }
    Invoke-CheckStep -Name "project-harness-audit" -Script { & .\scripts\audit-project-harness.ps1 }
    Invoke-CheckStep -Name "context-budget-audit" -Script { & .\scripts\audit-context-budget.ps1 }
    Invoke-CheckStep -Name "component-registry-audit" -Script { & .\scripts\audit-harness-components.ps1 }
    Invoke-CheckStep -Name "feature-list" -Script { & .\scripts\check-features.ps1 }
    Invoke-CheckStep -Name "tool-evals" -Script { & .\scripts\check-tool-evals.ps1 }
    Invoke-CheckStep -Name "architecture-check" -Script { & .\scripts\check-architecture.ps1 }
    Invoke-CheckStep -Name "worktree-audit" -Script { & .\scripts\audit-worktree.ps1 }

    if ($Runtime) {
        Invoke-CheckStep -Name "typescript" -Script { Invoke-Native -File "npx" -Args @("tsc", "-b", "--pretty", "false") }
        if (-not $SkipLint) {
            Invoke-CheckStep -Name "lint" -Script { Invoke-Native -File "npm" -Args @("run", "lint") }
        }
        if (-not $SkipBuild) {
            Invoke-CheckStep -Name "build" -Script { Invoke-Native -File "npm" -Args @("run", "build") }
        }
        if (-not $SkipCargo) {
            Invoke-CheckStep -Name "cargo-check" -Script { Invoke-Native -File "cargo" -Args @("check") -WorkingDirectory (Join-Path $root "src-tauri") }
        }
    }

    if ($Smoke) {
        Invoke-CheckStep -Name "canvas-smoke" -Script { & .\scripts\smoke-canvas.ps1 }
        Invoke-CheckStep -Name "routing-smoke" -Script { & .\scripts\smoke-routing.ps1 }
        Invoke-CheckStep -Name "persistence-smoke" -Script { & .\scripts\smoke-persistence.ps1 }
    }

    if ($TraceEvals) {
        if ($RealTraceEvals) {
            Invoke-CheckStep -Name "codex-trace-evals" -Script { & .\scripts\run-codex-trace-evals.ps1 -Limit 3 -AllowFailures }
        } else {
            Invoke-CheckStep -Name "codex-trace-evals-dry-run" -Script { & .\scripts\run-codex-trace-evals.ps1 -DryRun }
        }
    }
} finally {
    $failed = @($steps | Where-Object { $_.status -eq "failed" })
    $status = if ($failed.Count -gt 0) { "failed" } else { "passed" }
    $record = [ordered]@{
        schema = "check-all-v1"
        status = $status
        created_at = (Get-Date).ToString("o")
        root = $root
        runtime = [bool]$Runtime
        smoke = [bool]$Smoke
        trace_evals = [bool]$TraceEvals
        real_trace_evals = [bool]$RealTraceEvals
        steps = $steps
    }
    $record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    $stepLines = if ($steps.Count -gt 0) {
        ($steps | ForEach-Object { "- $($_.status): $($_.name) ($($_.duration_ms) ms)" }) -join "`r`n"
    } else {
        "- No steps ran."
    }

    $md = @"
# Check All

- Status: $status
- Created: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
- Runtime checks: $([bool]$Runtime)
- Smoke checks: $([bool]$Smoke)
- Trace evals: $([bool]$TraceEvals)
- Real trace evals: $([bool]$RealTraceEvals)

## Steps

$stepLines

## Artifacts

- check-all.json
- step logs in this folder
"@

    Set-Content -LiteralPath $summaryPath -Value $md -Encoding UTF8
}

[ordered]@{
    status = if (@($steps | Where-Object { $_.status -eq "failed" }).Count -gt 0) { "failed" } else { "success" }
    summary = "Check-all completed."
    artifacts = @($jsonPath, $summaryPath)
} | ConvertTo-Json -Depth 5 -Compress
