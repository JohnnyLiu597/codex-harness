param(
    [string]$ProjectRoot = ".",
    [string]$Name = "learning-intake",
    [string]$Source = "manual",
    [string]$Summary = "",
    [string]$FailureMode = "",
    [string]$Frequency = "one-off",
    [string]$ProposedDestination = "docs",
    [string[]]$Evidence = @(),
    [string[]]$NextActions = @(),
    [string[]]$Tags = @(),
    [string]$Route = "",
    [string]$SourceReference = ""
)

$ErrorActionPreference = "Stop"

function ConvertTo-Slug {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "learning-intake" }
    $slug = ($Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) { return "learning-intake" }
    return $slug
}

function Format-List {
    param([string[]]$Items)
    if ($Items.Count -eq 0) { return "- Not recorded." }
    return (($Items | ForEach-Object { "- $_" }) -join "`r`n")
}

$acceptedSources = @("test", "tool", "review", "ci", "runtime", "user", "conversation")
$acceptedRoutes = @("docs", "eval", "skill", "rule", "script", "component", "retire")
$routeAliases = @{
    "documentation" = "docs"
    "evals" = "eval"
    "trace-eval" = "eval"
    "tool-eval" = "eval"
    "skills" = "skill"
    "rules" = "rule"
    "scripts" = "script"
    "components" = "component"
    "retirement" = "retire"
}
$routeGuidance = @{
    "docs" = "Clarify durable operating or project guidance."
    "eval" = "Add or update a repeatable behavioral check."
    "skill" = "Improve reusable task guidance with a clear trigger."
    "rule" = "Capture a stable invariant that should apply consistently."
    "script" = "Automate deterministic repeated work or verification."
    "component" = "Review component ownership, evidence, cost, risk, or status."
    "retire" = "Run an explicit bounded retirement review before any state change."
}

$sourceKey = $Source.Trim().ToLowerInvariant()
$sourceType = if ($sourceKey -in $acceptedSources) {
    $sourceKey
} elseif ($sourceKey -eq "manual") {
    "manual"
} else {
    "legacy"
}

$routeWasExplicit = -not [string]::IsNullOrWhiteSpace($Route)
$requestedRoute = if ($routeWasExplicit) { $Route } else { $ProposedDestination }
if ([string]::IsNullOrWhiteSpace($requestedRoute)) { $requestedRoute = "docs" }
$routeKey = $requestedRoute.Trim().ToLowerInvariant()
if ($routeAliases.ContainsKey($routeKey)) { $routeKey = $routeAliases[$routeKey] }

$routeResolution = "canonical"
if ($routeKey -notin $acceptedRoutes) {
    if ($routeWasExplicit) {
        throw "Route must be one of: $($acceptedRoutes -join ', ')."
    }
    $routeKey = "docs"
    $routeResolution = "legacy-fallback"
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
$runDir = Join-Path $root ("artifacts\learning-inbox\" + $id)
$jsonPath = Join-Path $runDir "learning.json"
$summaryPath = Join-Path $runDir "summary.md"

New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$record = [ordered]@{
    schema = "codex-learning-intake-v2"
    id = $id
    created_at = (Get-Date).ToString("o")
    project_root = $root
    name = $Name
    source = $Source
    source_type = $sourceType
    source_reference = $SourceReference
    summary = $Summary
    failure_mode = $FailureMode
    frequency = $Frequency
    proposed_destination = $ProposedDestination
    requested_route = $requestedRoute
    route = $routeKey
    route_resolution = $routeResolution
    route_guidance = $routeGuidance[$routeKey]
    evidence = $Evidence
    next_actions = $NextActions
    tags = $Tags
    automatic_destination_changes = $false
}

$record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$md = @"
# Learning Intake

- ID: $id
- Source: $Source
- Source Type: $sourceType
- Source Reference: $SourceReference
- Frequency: $Frequency
- Proposed Destination: $ProposedDestination
- Route: $routeKey
- Route Resolution: $routeResolution
- Automatic Destination Changes: False
- Created: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
- Project: $root

## Summary

$Summary

## Failure Mode

$FailureMode

## Route Guidance

$($routeGuidance[$routeKey])

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
    summary = "Learning intake record created."
    id = $id
    source_type = $sourceType
    route = $routeKey
    route_resolution = $routeResolution
    automatic_destination_changes = $false
    artifacts = @($jsonPath, $summaryPath)
} | ConvertTo-Json -Depth 5 -Compress
