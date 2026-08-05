param(
    [string]$ProjectRoot = ".",
    [Parameter(Mandatory = $true)][string]$Tool,
    [ValidateSet("timeout", "schema-error", "permission", "auth", "quota", "wrong-target", "bad-output", "network", "mcp", "browser-state", "desktop-state", "other")]
    [string]$FailureType = "other",
    [string]$Name = "",
    [string]$Status = "captured",
    [string]$Summary = "",
    [string]$Operation = "",
    [Alias("Error")]
    [string]$ErrorText = "",
    [string]$Recovery = "",
    [string]$ProposedDestination = "triage",
    [string[]]$Evidence = @(),
    [string[]]$NextActions = @(),
    [string[]]$Tags = @()
)

$ErrorActionPreference = "Stop"

function ConvertTo-Slug {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "tool-failure" }
    $slug = ($Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) { return "tool-failure" }
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
if (-not $Name) { $Name = "$Tool $FailureType" }
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$id = "$stamp-$(ConvertTo-Slug -Value $Name)"
$runDir = Join-Path $root ("artifacts\tool-failures\" + $id)
$jsonPath = Join-Path $runDir "tool-failure.json"
$summaryPath = Join-Path $runDir "summary.md"

New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$record = [ordered]@{
    schema = "codex-tool-failure-v1"
    id = $id
    created_at = (Get-Date).ToString("o")
    project_root = $root
    tool = $Tool
    failure_type = $FailureType
    name = $Name
    status = $Status
    summary = $Summary
    operation = $Operation
    error = $ErrorText
    recovery = $Recovery
    proposed_destination = $ProposedDestination
    evidence = $Evidence
    next_actions = $NextActions
    tags = $Tags
}
$record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$md = @"
# Tool Failure

- ID: $id
- Tool: $Tool
- Failure Type: $FailureType
- Status: $Status
- Proposed Destination: $ProposedDestination
- Created: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
- Project: $root

## Summary

$Summary

## Operation

$Operation

## Error

$ErrorText

## Recovery

$Recovery

## Evidence

$(Format-List -Items $Evidence)

## Next Actions

$(Format-List -Items $NextActions)

## Tags

$(Format-List -Items $Tags)
"@
Set-Content -LiteralPath $summaryPath -Value $md -Encoding UTF8

[ordered]@{
    status = "success"
    summary = "Tool failure record created."
    id = $id
    artifacts = @($jsonPath, $summaryPath)
} | ConvertTo-Json -Depth 5 -Compress
