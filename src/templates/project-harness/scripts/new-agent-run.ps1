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
    [string]$ParentRunId = ""
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

if ($ProjectRoot -eq ".") {
    $scriptProjectRoot = Join-Path $PSScriptRoot ".."
    if ((Test-Path -LiteralPath (Join-Path $scriptProjectRoot "mission.md")) -and
        (Test-Path -LiteralPath (Join-Path $scriptProjectRoot "CONTEXT.md"))) {
        $ProjectRoot = $scriptProjectRoot
    }
}
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$id = "$stamp-$(ConvertTo-Slug -Value $Name)"
$runDir = Join-Path $root ("artifacts\agent-runs\" + $id)
$jsonPath = Join-Path $runDir "agent-run.json"
$summaryPath = Join-Path $runDir "summary.md"

New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$record = [ordered]@{
    schema = "codex-agent-run-v1"
    id = $id
    parent_run_id = $ParentRunId
    created_at = (Get-Date).ToString("o")
    project_root = $root
    name = $Name
    role = $Role
    task = $Task
    status = $Status
    inputs = $Inputs
    outputs = $Outputs
    files = $Files
    checks = $Checks
    risks = $Risks
    handoff = $Handoff
}

$record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$md = @"
# Agent Run

- ID: $id
- Parent Run: $ParentRunId
- Role: $Role
- Status: $Status
- Created: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
- Project: $root

## Task

$Task

## Inputs

$(Format-List -Items $Inputs)

## Outputs

$(Format-List -Items $Outputs)

## Files

$(Format-List -Items $Files)

## Checks

$(Format-List -Items $Checks)

## Risks

$(Format-List -Items $Risks)

## Handoff

$Handoff
"@

Set-Content -LiteralPath $summaryPath -Value $md -Encoding UTF8

[ordered]@{
    status = "success"
    summary = "Agent run record created."
    id = $id
    artifacts = @($jsonPath, $summaryPath)
} | ConvertTo-Json -Depth 5 -Compress
