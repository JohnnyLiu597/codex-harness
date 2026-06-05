param(
    [ValidateSet("plan", "verify", "tdd", "e2e", "review", "security", "learn", "checkpoint", "orchestrate")]
    [string]$Workflow = "verify",
    [string]$ProjectRoot = ".",
    [string]$Task = "",
    [switch]$Run,
    [switch]$ContinueOnError
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$safeWorkflow = $Workflow.ToLowerInvariant()
$runDir = Join-Path $root ("artifacts\workflows\$stamp-$safeWorkflow")
$jsonPath = Join-Path $runDir "workflow.json"
$summaryPath = Join-Path $runDir "summary.md"
$steps = New-Object System.Collections.Generic.List[object]

New-Item -ItemType Directory -Force -Path $runDir | Out-Null

function Add-Step {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Detail = "",
        [string]$Command = ""
    )

    $steps.Add([pscustomobject]@{
        name = $Name
        status = $Status
        command = $Command
        detail = $Detail
    }) | Out-Null
}

function Get-TestSurface {
    $script = Join-Path $PSScriptRoot "detect-project-test-surface.ps1"
    if (-not (Test-Path -LiteralPath $script)) {
        Add-Step -Name "detect-test-surface" -Status "failed" -Detail "detect-project-test-surface.ps1 not found"
        return $null
    }

    $output = & $script -ProjectRoot $root
    Add-Step -Name "detect-test-surface" -Status "passed" -Detail "Project test surface detected."
    return ($output | ConvertFrom-Json)
}

function Invoke-ProjectCommand {
    param(
        [string]$Name,
        [string]$Command
    )

    $safeName = ($Name -replace '[^a-zA-Z0-9]+', '-').Trim('-').ToLowerInvariant()
    $logPath = Join-Path $runDir "$safeName.log"
    try {
        Push-Location $root
        try {
            $output = powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $Command 2>&1
            $text = ($output | Out-String).Trim()
            Set-Content -LiteralPath $logPath -Value $text -Encoding UTF8
            Add-Step -Name $Name -Status "passed" -Command $Command -Detail $logPath
        } finally {
            Pop-Location
        }
    } catch {
        Set-Content -LiteralPath $logPath -Value $_.Exception.Message -Encoding UTF8
        Add-Step -Name $Name -Status "failed" -Command $Command -Detail $logPath
        if (-not $ContinueOnError) {
            throw "Workflow command failed: $Command. See $logPath"
        }
    }
}

function Get-WorkflowPlan {
    param([object]$Surface)

    switch ($Workflow) {
        "plan" {
            return @(
                "Read nearest AGENTS.md, mission.md, CONTEXT.md, MEMORY.md, README.md.",
                "Use planner agent for complex implementation or architecture work.",
                "Create or update artifacts/plan_<task>.md for major work.",
                "Define verification mode before editing."
            )
        }
        "verify" {
            return @($Surface.recommended.quick | ForEach-Object { $_.command })
        }
        "tdd" {
            return @(
                "Use tester/tdd workflow: write or identify the failing test first.",
                "Run the targeted failing test.",
                "Implement the smallest fix.",
                "Run targeted test again, then nearest broader gate."
            )
        }
        "e2e" {
            return @($Surface.recommended.runtime | Where-Object { $_.kind -in @("e2e", "smoke", "runtime") } | ForEach-Object { $_.command })
        }
        "review" {
            return @(
                "Use reviewer agent after code changes.",
                "Run git diff and inspect modified files first.",
                "Lead findings with correctness, security, regressions, and missing tests."
            )
        }
        "security" {
            return @(
                "Use security-reviewer for auth, secrets, API endpoints, user input, payments, or sensitive data.",
                "Run dependency or secret checks when configured by the project.",
                "Do not print secret values; report only key names or file presence."
            )
        }
        "learn" {
            return @(
                "If this is a repeated miss, create a learning intake.",
                "Promote the lesson to docs, eval, skill, rule, or script only after triage.",
                "Prefer trace evals for repeated Codex behavior misses."
            )
        }
        "checkpoint" {
            return @(
                "Capture git status, verification status, and next action.",
                "Create a session summary for long-running or interrupted work.",
                "Keep generated artifacts out of commits unless the project wants them."
            )
        }
        "orchestrate" {
            return @(
                "Decompose into planner -> executor/tester -> reviewer/security -> verifier.",
                "Use new-agent-run.ps1 for delegated worker contracts.",
                "Merge worker outputs into one final answer; do not paste raw worker logs."
            )
        }
    }
}

$surface = Get-TestSurface
$plan = Get-WorkflowPlan -Surface $surface
foreach ($item in $plan) {
    Add-Step -Name "workflow-plan" -Status "planned" -Detail $item
}

if ($Run -and $Workflow -eq "verify" -and $surface) {
    foreach ($cmd in @($surface.recommended.quick | Select-Object -First 4)) {
        Invoke-ProjectCommand -Name $cmd.kind -Command $cmd.command
    }
} elseif ($Run) {
    Add-Step -Name "run" -Status "skipped" -Detail "Automatic run is only supported for the verify workflow."
}

$failed = @($steps | Where-Object { $_.status -eq "failed" })
$status = if ($failed.Count -gt 0) { "failed" } else { "success" }

$record = [ordered]@{
    schema = "codex-workflow-run-v1"
    status = $status
    workflow = $Workflow
    task = $Task
    created_at = (Get-Date).ToString("o")
    project_root = $root
    run_requested = [bool]$Run
    steps = $steps.ToArray()
    test_surface = $surface
}
$record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$stepLines = if ($steps.Count -gt 0) {
    ($steps | ForEach-Object {
        $commandText = if ($_.command) { " command='$($_.command)'" } else { "" }
        "- {0}: {1}{2} - {3}" -f $_.status, $_.name, $commandText, $_.detail
    }) -join "`r`n"
} else {
    "- No steps recorded."
}

$md = @"
# Codex Workflow

- Status: $status
- Workflow: $Workflow
- Task: $Task
- Created: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
- Project: $root

## Steps

$stepLines

## Artifacts

- workflow.json
- summary.md
"@

Set-Content -LiteralPath $summaryPath -Value $md -Encoding UTF8

[ordered]@{
    status = $status
    summary = "Codex workflow recorded."
    workflow = $Workflow
    artifacts = @($jsonPath, $summaryPath)
} | ConvertTo-Json -Depth 5 -Compress
