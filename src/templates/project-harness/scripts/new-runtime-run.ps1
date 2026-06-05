param(
    [string]$ProjectRoot = ".",
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Status = "completed",
    [string]$Scope = "runtime",
    [string]$Environment = "local",
    [string]$Summary = "",
    [string[]]$FeatureIds = @(),
    [string[]]$Commands = @(),
    [string[]]$Checks = @(),
    [string[]]$Evidence = @(),
    [string[]]$Artifacts = @(),
    [string[]]$Risks = @(),
    [string[]]$NextActions = @(),
    [switch]$UpdateFeatureEvidence,
    [switch]$MarkFeaturesPassed
)

$ErrorActionPreference = "Stop"

function ConvertTo-Slug {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "runtime-run" }
    $slug = ($Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) { return "runtime-run" }
    return $slug
}

function Format-List {
    param([string[]]$Items)
    if ($Items.Count -eq 0) { return "- Not recorded." }
    return (($Items | ForEach-Object { "- $_" }) -join "`r`n")
}

function ConvertTo-StringArray {
    param([object]$Value)
    $items = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Value) { return @() }
    foreach ($item in @($Value)) {
        if ($null -ne $item -and -not [string]::IsNullOrWhiteSpace([string]$item)) {
            $items.Add([string]$item) | Out-Null
        }
    }
    return $items.ToArray()
}

function Set-JsonProperty {
    param(
        [Parameter(Mandatory = $true)][object]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [object]$Value
    )

    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.$Name = $Value
    } else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
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
$runDir = Join-Path $root ("artifacts\runtime-runs\" + $id)
$jsonPath = Join-Path $runDir "runtime.json"
$summaryPath = Join-Path $runDir "summary.md"
$relativeSummary = "artifacts/runtime-runs/$id/summary.md"
$linkedFeatureIds = New-Object System.Collections.Generic.List[string]

New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$record = [ordered]@{
    schema = "codex-runtime-run-v1"
    id = $id
    created_at = (Get-Date).ToString("o")
    project_root = $root
    name = $Name
    status = $Status
    scope = $Scope
    environment = $Environment
    summary = $Summary
    feature_ids = $FeatureIds
    commands = $Commands
    checks = $Checks
    evidence = $Evidence
    artifacts = $Artifacts
    risks = $Risks
    next_actions = $NextActions
}

$record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

if ($UpdateFeatureEvidence) {
    if ($FeatureIds.Count -eq 0) {
        throw "-UpdateFeatureEvidence requires at least one -FeatureIds entry."
    }

    $featurePath = Join-Path $root "docs\features.json"
    if (-not (Test-Path -LiteralPath $featurePath)) {
        throw "Feature list not found: $featurePath"
    }

    if ($MarkFeaturesPassed -and ($Status -notin @("completed", "passed", "success"))) {
        throw "-MarkFeaturesPassed requires Status completed, passed, or success."
    }

    $featureDoc = Get-Content -LiteralPath $featurePath -Raw | ConvertFrom-Json
    $knownIds = @($featureDoc.features | ForEach-Object { [string]$_.id })
    $missingIds = @($FeatureIds | Where-Object { $_ -notin $knownIds })
    if ($missingIds.Count -gt 0) {
        throw "Feature ids not found: $($missingIds -join ', ')"
    }

    foreach ($feature in @($featureDoc.features)) {
        if ([string]$feature.id -notin $FeatureIds) { continue }

        $entry = "runtime-run:$($id):$relativeSummary"
        $existing = @(ConvertTo-StringArray -Value $feature.evidence)
        if ($entry -notin $existing) {
            Set-JsonProperty -Object $feature -Name "evidence" -Value @($existing + $entry)
        }
        Set-JsonProperty -Object $feature -Name "last_checked" -Value (Get-Date).ToString("yyyy-MM-dd")
        if ($MarkFeaturesPassed) {
            Set-JsonProperty -Object $feature -Name "passes" -Value $true
        }
        $linkedFeatureIds.Add([string]$feature.id) | Out-Null
    }

    Set-JsonProperty -Object $featureDoc -Name "updated_at" -Value (Get-Date).ToString("yyyy-MM-dd")
    $featureDoc | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $featurePath -Encoding UTF8
}

$featureLines = if ($FeatureIds.Count -gt 0) {
    ($FeatureIds | ForEach-Object { "- $_" }) -join "`r`n"
} else {
    "- Not linked."
}

$md = @"
# Runtime Run

- ID: $id
- Name: $Name
- Status: $Status
- Scope: $Scope
- Environment: $Environment
- Created: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
- Project: $root

## Summary

$Summary

## Feature IDs

$featureLines

## Commands

$(Format-List -Items $Commands)

## Checks

$(Format-List -Items $Checks)

## Evidence

$(Format-List -Items $Evidence)

## Artifacts

$(Format-List -Items $Artifacts)

## Risks

$(Format-List -Items $Risks)

## Next Actions

$(Format-List -Items $NextActions)
"@

Set-Content -LiteralPath $summaryPath -Value $md -Encoding UTF8

[ordered]@{
    status = "success"
    summary = "Runtime run record created."
    id = $id
    artifacts = @($jsonPath, $summaryPath)
    linked_feature_ids = $linkedFeatureIds.ToArray()
} | ConvertTo-Json -Depth 5 -Compress
