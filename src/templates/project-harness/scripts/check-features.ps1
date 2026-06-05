param(
    [string]$FeatureFile = ""
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
if (-not $FeatureFile) {
    $FeatureFile = Join-Path $root "docs\features.json"
}

if (-not (Test-Path -LiteralPath $FeatureFile)) {
    throw "Feature list not found: $FeatureFile"
}

$raw = Get-Content -LiteralPath $FeatureFile -Raw
$json = $raw | ConvertFrom-Json

if ($json.schema -ne "codex-feature-list-v1") {
    throw "Unexpected feature list schema: $($json.schema)"
}
if (-not $json.features -or $json.features.Count -eq 0) {
    throw "Feature list has no features."
}

$ids = New-Object System.Collections.Generic.HashSet[string]
$missing = New-Object System.Collections.Generic.List[string]
$duplicates = New-Object System.Collections.Generic.List[string]
$evidenceFailures = New-Object System.Collections.Generic.List[string]
$passed = 0
$open = 0
$criticalOpen = 0

function Test-HasNonEmptyItems {
    param([object]$Value)

    if ($null -eq $Value) { return $false }
    foreach ($item in @($Value)) {
        if ($null -ne $item -and -not [string]::IsNullOrWhiteSpace([string]$item)) {
            return $true
        }
    }
    return $false
}

foreach ($feature in $json.features) {
    foreach ($field in @("id", "category", "description", "status", "passes", "priority", "steps")) {
        if ($null -eq $feature.$field -or [string]::IsNullOrWhiteSpace([string]$feature.$field)) {
            $missing.Add("$($feature.id): missing $field") | Out-Null
        }
    }
    if ($feature.id -and -not $ids.Add([string]$feature.id)) {
        $duplicates.Add([string]$feature.id) | Out-Null
    }
    if (-not (Test-HasNonEmptyItems $feature.steps)) {
        $missing.Add("$($feature.id): missing steps") | Out-Null
    }
    if ($feature.passes -eq $true) {
        if (-not (Test-HasNonEmptyItems $feature.evidence)) {
            $evidenceFailures.Add("$($feature.id): passes=true requires at least one evidence entry") | Out-Null
        }
        if ([string]::IsNullOrWhiteSpace([string]$feature.last_checked)) {
            $evidenceFailures.Add("$($feature.id): passes=true requires last_checked") | Out-Null
        } else {
            $checked = [datetime]::MinValue
            if (-not [datetime]::TryParse([string]$feature.last_checked, [ref]$checked)) {
                $evidenceFailures.Add("$($feature.id): last_checked is not a parseable date") | Out-Null
            }
        }
        $passed += 1
    } else {
        $open += 1
        if ($feature.priority -eq "critical") {
            $criticalOpen += 1
        }
    }
}

if ($missing.Count -gt 0) {
    throw "Invalid feature entries: $($missing -join '; ')"
}
if ($duplicates.Count -gt 0) {
    throw "Duplicate feature ids: $($duplicates -join ', ')"
}
if ($evidenceFailures.Count -gt 0) {
    throw "Feature evidence gate failed: $($evidenceFailures -join '; ')"
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runDir = Join-Path $root ("artifacts\feature-checks\" + $stamp)
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$summaryPath = Join-Path $runDir "summary.md"
$jsonPath = Join-Path $runDir "features-check.json"

$record = [ordered]@{
    schema = "feature-check-v1"
    status = "passed"
    created_at = (Get-Date).ToString("o")
    feature_file = $FeatureFile
    total = $json.features.Count
    passed = $passed
    open = $open
    critical_open = $criticalOpen
    evidence_gate = "passed features require evidence and last_checked"
}
$record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$md = @"
# Feature Check

- Status: passed
- Total: $($json.features.Count)
- Passing: $passed
- Open or needs verification: $open
- Critical open: $criticalOpen
- Evidence gate: passed features require evidence and last_checked
"@

Set-Content -LiteralPath $summaryPath -Value $md -Encoding UTF8

[ordered]@{
    status = "success"
    summary = "Feature list validated."
    total = $json.features.Count
    passed = $passed
    open = $open
    critical_open = $criticalOpen
    artifacts = @($jsonPath, $summaryPath)
} | ConvertTo-Json -Depth 5 -Compress
