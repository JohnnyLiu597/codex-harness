param(
    [string]$ProjectRoot = ".",
    [string]$Name = "agent-run",
    [string]$Role = "worker",
    [string]$Task = "",
    [string]$Status = "planned",
    [string[]]$Inputs = @(),
    [string[]]$Outputs = @(),
    [string[]]$Files = @(),
    [string[]]$Checks = @(),
    [string[]]$Risks = @(),
    [string]$Handoff = "",
    [string]$ParentRunId = "",
    [string]$AttemptId = "",
    [string[]]$Ownership = @(),
    [ValidateSet("shared", "branch", "worktree", "none")][string]$IsolationMode = "shared",
    [string]$Worktree = "",
    [string]$Branch = "",
    [string]$CheckerIdentity = "",
    [string]$VerificationArtifact = "",
    [string]$HandoffSummary = "",
    [long]$TokenBudget = 0,
    [double]$CostBudget = 0,
    [int]$TimeBudgetMinutes = 0,
    [int]$IterationBudget = 0,
    [int]$WorkerBudget = 0,
    [string]$StopReason = "",
    [string]$LastVerifiedCommit = "",
    [switch]$PersistInputs
)

$ErrorActionPreference = "Stop"

function ConvertTo-Slug {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "agent-run" }
    $slug = ($Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) { return "agent-run" }
    return $slug
}

function Format-List {
    param([string[]]$Items)
    if ($Items.Count -eq 0) { return "- Not recorded." }
    return (($Items | ForEach-Object { "- $_" }) -join "`r`n")
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

function Format-InputHashes {
    param([object[]]$Hashes)
    if ($Hashes.Count -eq 0) { return "- Not recorded." }
    return (($Hashes | ForEach-Object { "- [$($_.index)] sha256:$($_.sha256)" }) -join "`r`n")
}

foreach ($budget in @($TokenBudget, $CostBudget, $TimeBudgetMinutes, $IterationBudget, $WorkerBudget)) {
    if ($budget -lt 0) { throw "Agent run budgets cannot be negative." }
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
$id = "$stamp-$(ConvertTo-Slug -Value $Name)"
$runDir = Join-Path $root ("artifacts\agent-runs\" + $id)
$jsonPath = Join-Path $runDir "agent-run.json"
$summaryPath = Join-Path $runDir "summary.md"
$createdAt = Get-Date
$resolvedAttemptId = if ([string]::IsNullOrWhiteSpace($AttemptId)) { "$id-attempt-1" } else { $AttemptId }
$resolvedWorktree = if ([string]::IsNullOrWhiteSpace($Worktree)) { $root } else { $Worktree }
$resolvedBranch = $Branch
if ([string]::IsNullOrWhiteSpace($resolvedBranch)) {
    try {
        $resolvedBranch = (git -C $root branch --show-current 2>$null | Out-String).Trim()
    } catch {
        $resolvedBranch = ""
    }
}
$resolvedHandoffSummary = if ([string]::IsNullOrWhiteSpace($HandoffSummary)) { $Handoff } else { $HandoffSummary }
$inputHashes = @(
    for ($index = 0; $index -lt $Inputs.Count; $index++) {
        [ordered]@{
            index = $index
            sha256 = Get-StringSha256 -Value $Inputs[$index]
        }
    }
)
$persistedInputs = if ($PersistInputs) { $Inputs } else { @() }
$inputDisplay = if ($PersistInputs) { Format-List -Items $Inputs } else { "- Not persisted. Use the input hashes below." }

New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$record = [ordered]@{
    schema = "codex-agent-run-v2"
    id = $id
    attempt_id = $resolvedAttemptId
    parent_run_id = $ParentRunId
    created_at = $createdAt.ToString("o")
    project_root = $root
    name = $Name
    role = $Role
    task = $Task
    status = $Status
    ownership = $Ownership
    isolation_mode = $IsolationMode
    worktree = $resolvedWorktree
    branch = $resolvedBranch
    inputs = $persistedInputs
    input_count = $Inputs.Count
    inputs_persisted = [bool]$PersistInputs
    input_hash_algorithm = "SHA-256"
    input_hashes = $inputHashes
    outputs = $Outputs
    files = $Files
    checks = $Checks
    risks = $Risks
    checker_identity = $CheckerIdentity
    verification_artifact = $VerificationArtifact
    handoff = $Handoff
    handoff_summary = $resolvedHandoffSummary
    budgets = [ordered]@{
        token_budget = $TokenBudget
        cost_budget = $CostBudget
        time_budget_minutes = $TimeBudgetMinutes
        iteration_budget = $IterationBudget
        worker_budget = $WorkerBudget
    }
    stop_reason = $StopReason
    last_verified_commit = $LastVerifiedCommit
}

$record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$md = @"
# Agent Run

- ID: $id
- Attempt ID: $resolvedAttemptId
- Parent Run: $ParentRunId
- Role: $Role
- Status: $Status
- Checker: $CheckerIdentity
- Isolation Mode: $IsolationMode
- Worktree: $resolvedWorktree
- Branch: $resolvedBranch
- Last Verified Commit: $LastVerifiedCommit
- Created: $($createdAt.ToString("yyyy-MM-dd HH:mm:ss"))
- Project: $root

## Task

$Task

## Ownership

$(Format-List -Items $Ownership)

## Inputs

$inputDisplay

## Input Hashes

$(Format-InputHashes -Hashes $inputHashes)

## Outputs

$(Format-List -Items $Outputs)

## Files

$(Format-List -Items $Files)

## Checks

$(Format-List -Items $Checks)

## Risks

$(Format-List -Items $Risks)

## Verification Artifact

$VerificationArtifact

## Budgets

- Tokens: $TokenBudget
- Cost: $CostBudget
- Time Minutes: $TimeBudgetMinutes
- Iterations: $IterationBudget
- Workers: $WorkerBudget

## Handoff Summary

$resolvedHandoffSummary

## Stop Reason

$StopReason
"@

Set-Content -LiteralPath $summaryPath -Value $md -Encoding UTF8

[ordered]@{
    status = "success"
    summary = "Agent run record created."
    id = $id
    inputs_persisted = [bool]$PersistInputs
    artifacts = @($jsonPath, $summaryPath)
} | ConvertTo-Json -Depth 5 -Compress
