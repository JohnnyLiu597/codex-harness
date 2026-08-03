param(
    [string]$ProjectRoot = ".",
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$ComponentId,
    [Parameter(Mandatory = $true)][string]$Hypothesis,
    [string]$Baseline = "Component present under the normal workflow.",
    [string]$Variant = "Component omitted only inside the bounded comparison.",
    [ValidateRange(1, 10000)][int]$MaxCases = 10,
    [ValidateRange(1, 1440)][int]$MaxMinutes = 30,
    [ValidateSet("planned", "running", "completed", "inconclusive", "cancelled")]
    [string]$Status = "planned",
    [string[]]$Metrics = @("completion quality", "verification result"),
    [string[]]$Controls = @(),
    [string[]]$Evidence = @(),
    [string[]]$Risks = @(),
    [string[]]$StopConditions = @(
        "Stop when the case bound is reached.",
        "Stop when the time bound is reached.",
        "Stop on safety, privacy, or data-integrity risk."
    ),
    [string]$Outcome = "",
    [string]$Decision = "pending",
    [string[]]$NextActions = @(),
    [string[]]$Tags = @()
)

$ErrorActionPreference = "Stop"

function ConvertTo-Slug {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "ablation-run" }
    $slug = ($Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) { return "ablation-run" }
    return $slug
}

function Format-List {
    param([string[]]$Items)
    if ($Items.Count -eq 0) { return "- Not recorded." }
    return (($Items | ForEach-Object { "- $_" }) -join "`r`n")
}

if ([string]::IsNullOrWhiteSpace($ComponentId)) { throw "ComponentId must not be empty." }
if ([string]::IsNullOrWhiteSpace($Hypothesis)) { throw "Hypothesis must not be empty." }
if ([string]::IsNullOrWhiteSpace($Baseline)) { throw "Baseline must not be empty." }
if ([string]::IsNullOrWhiteSpace($Variant)) { throw "Variant must not be empty." }
if ($Metrics.Count -eq 0) { throw "At least one metric is required." }
if ($StopConditions.Count -eq 0) { throw "At least one stop condition is required." }

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
$runDir = Join-Path $root ("artifacts\ablation-runs\" + $id)
$jsonPath = Join-Path $runDir "ablation.json"
$summaryPath = Join-Path $runDir "summary.md"

New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$record = [ordered]@{
    schema = "codex-ablation-run-v1"
    id = $id
    created_at = (Get-Date).ToString("o")
    project_root = $root
    name = $Name
    component_id = $ComponentId
    status = $Status
    hypothesis = $Hypothesis
    comparison = [ordered]@{
        baseline = $Baseline
        variant = $Variant
    }
    bounds = [ordered]@{
        max_cases = $MaxCases
        max_minutes = $MaxMinutes
    }
    metrics = $Metrics
    controls = $Controls
    evidence = $Evidence
    risks = $Risks
    stop_conditions = $StopConditions
    outcome = $Outcome
    decision = $Decision
    next_actions = $NextActions
    tags = $Tags
    automatic_component_changes = $false
    component_state_changed = $false
}

$record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$md = @"
# Ablation Run

- ID: $id
- Name: $Name
- Component: $ComponentId
- Status: $Status
- Max Cases: $MaxCases
- Max Minutes: $MaxMinutes
- Automatic Component Changes: False
- Component State Changed: False
- Created: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
- Project: $root

## Hypothesis

$Hypothesis

## Baseline

$Baseline

## Variant

$Variant

## Metrics

$(Format-List -Items $Metrics)

## Controls

$(Format-List -Items $Controls)

## Evidence

$(Format-List -Items $Evidence)

## Risks

$(Format-List -Items $Risks)

## Stop Conditions

$(Format-List -Items $StopConditions)

## Outcome

$Outcome

## Decision

$Decision

## Next Actions

$(Format-List -Items $NextActions)

## Tags

$(Format-List -Items $Tags)
"@

Set-Content -LiteralPath $summaryPath -Value $md -Encoding UTF8

[ordered]@{
    status = "success"
    summary = "Bounded ablation record created without changing component state."
    id = $id
    automatic_component_changes = $false
    component_state_changed = $false
    artifacts = @($jsonPath, $summaryPath)
} | ConvertTo-Json -Depth 5 -Compress
