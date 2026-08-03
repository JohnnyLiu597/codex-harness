param(
    [string]$ProjectRoot = ".",
    [Parameter(Mandatory = $true)][string]$Name,
    [ValidateSet("goal", "subagent", "worktree", "scheduled", "event-driven", "manual")]
    [string]$WorkType = "manual",
    [Alias("Status")]
    [ValidateSet("queued", "running", "checking", "waiting_approval", "passed", "blocked", "stopped")]
    [string]$State = "queued",
    [string]$JobId = "",
    [string]$ParentJobId = "",
    [string]$NativeId = "",
    [string]$IdempotencyKey = "",
    [int]$Attempt = 1,
    [string]$ResumeCursor = "",
    [long]$TokenBudget = 0,
    [double]$CostBudget = 0,
    [int]$TimeBudgetMinutes = 0,
    [int]$IterationBudget = 0,
    [int]$WorkerBudget = 0,
    [string]$NetworkPolicy = "inherit",
    [string]$LastVerifiedCommit = "",
    [string]$StopReason = "",
    [string[]]$Artifacts = @(),
    [string]$Summary = ""
)

$ErrorActionPreference = "Stop"

function ConvertTo-Slug {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "job" }
    $slug = ($Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) { return "job" }
    return $slug
}

function Get-StringSha256 {
    param([AllowEmptyString()][string]$Value)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Value)
        $hash = $sha256.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash) -replace "-", "").ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
}

function Format-List {
    param([string[]]$Items)
    if ($Items.Count -eq 0) { return "- Not recorded." }
    return (($Items | ForEach-Object { "- $_" }) -join "`r`n")
}

if ($Attempt -lt 1) {
    throw "Attempt must be greater than or equal to one."
}
foreach ($budget in @($TokenBudget, $CostBudget, $TimeBudgetMinutes, $IterationBudget, $WorkerBudget)) {
    if ($budget -lt 0) { throw "Job budgets cannot be negative." }
}

if ($ProjectRoot -eq ".") {
    $scriptProjectRoot = Join-Path $PSScriptRoot ".."
    if ((Test-Path -LiteralPath (Join-Path $scriptProjectRoot "mission.md")) -and
        (Test-Path -LiteralPath (Join-Path $scriptProjectRoot "CONTEXT.md"))) {
        $ProjectRoot = $scriptProjectRoot
    }
}

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$stamp = Get-Date -Format "yyyyMMdd-HHmmssfff"
if ([string]::IsNullOrWhiteSpace($JobId)) {
    $id = "$stamp-$(ConvertTo-Slug -Value $Name)"
} else {
    if ($JobId -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]*$') {
        throw "JobId may contain only letters, numbers, dot, underscore, and dash."
    }
    $id = $JobId
}

$resolvedIdempotencyKey = if ([string]::IsNullOrWhiteSpace($IdempotencyKey)) {
    "sha256:" + (Get-StringSha256 -Value ($WorkType + "`n" + $Name))
} else {
    $IdempotencyKey
}
$warnings = New-Object System.Collections.Generic.List[string]
if ($State -in @("blocked", "stopped") -and [string]::IsNullOrWhiteSpace($StopReason)) {
    $warnings.Add("stop_reason_missing") | Out-Null
}
if ($State -eq "passed" -and
    [string]::IsNullOrWhiteSpace($LastVerifiedCommit) -and
    $Artifacts.Count -eq 0) {
    $warnings.Add("passing_evidence_missing") | Out-Null
}

$recordedAt = Get-Date
$runDir = Join-Path $root ("artifacts\job-states\" + $id)
$jsonPath = Join-Path $runDir "job-state.json"
$summaryPath = Join-Path $runDir "summary.md"
$historyPath = Join-Path $runDir "history.jsonl"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$record = [ordered]@{
    schema = "codex-job-state-v1"
    record_kind = "adapter"
    id = $id
    parent_job_id = $ParentJobId
    name = $Name
    recorded_at = $recordedAt.ToString("o")
    project_root = $root
    work_type = $WorkType
    state = $State
    adapter = [ordered]@{
        native_work_type = $WorkType
        native_id = $NativeId
        canonical_state = $State
    }
    idempotency_key = $resolvedIdempotencyKey
    attempt = $Attempt
    resume_cursor = $ResumeCursor
    budgets = [ordered]@{
        token_budget = $TokenBudget
        cost_budget = $CostBudget
        time_budget_minutes = $TimeBudgetMinutes
        iteration_budget = $IterationBudget
        worker_budget = $WorkerBudget
    }
    network_policy = $NetworkPolicy
    last_verified_commit = $LastVerifiedCommit
    stop_reason = $StopReason
    artifacts = $Artifacts
    summary = $Summary
    warnings = $warnings.ToArray()
}
$record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$record | ConvertTo-Json -Depth 10 -Compress | Add-Content -LiteralPath $historyPath -Encoding UTF8

$warningLines = if ($warnings.Count -gt 0) {
    ($warnings | ForEach-Object { "- $_" }) -join "`r`n"
} else {
    "- None."
}

$md = @"
# Job State

- ID: $id
- Parent Job: $ParentJobId
- Name: $Name
- Native Work Type: $WorkType
- Native ID: $NativeId
- State: $State
- Attempt: $Attempt
- Idempotency Key: $resolvedIdempotencyKey
- Resume Cursor: $ResumeCursor
- Network Policy: $NetworkPolicy
- Last Verified Commit: $LastVerifiedCommit
- Recorded: $($recordedAt.ToString("yyyy-MM-dd HH:mm:ss"))
- Project: $root

## Summary

$Summary

## Budgets

- Tokens: $TokenBudget
- Cost: $CostBudget
- Time Minutes: $TimeBudgetMinutes
- Iterations: $IterationBudget
- Workers: $WorkerBudget

## Stop Reason

$StopReason

## Artifacts

$(Format-List -Items $Artifacts)

## Record Warnings

$warningLines

This file records observed state only. It does not schedule, execute, resume,
approve, or stop work.
"@
Set-Content -LiteralPath $summaryPath -Value $md -Encoding UTF8

[ordered]@{
    status = if ($warnings.Count -eq 0) { "success" } else { "warning" }
    summary = "Job state record created."
    id = $id
    state = $State
    artifacts = @($jsonPath, $summaryPath, $historyPath)
    warnings = $warnings.ToArray()
} | ConvertTo-Json -Depth 6 -Compress
