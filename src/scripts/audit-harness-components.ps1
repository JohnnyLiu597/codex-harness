param(
    [string]$ProjectRoot = "",
    [string]$RegistryPath = "",
    [datetime]$AsOfDate = (Get-Date),
    [switch]$FailOnWarnings
)

$ErrorActionPreference = "Stop"

function Add-Issue {
    param(
        [System.Collections.Generic.List[object]]$List,
        [Parameter(Mandatory = $true)][string]$Code,
        [string]$ComponentId = "",
        [Parameter(Mandatory = $true)][string]$Detail
    )

    $List.Add([pscustomobject]@{
        code = $Code
        component_id = $ComponentId
        detail = $Detail
    }) | Out-Null
}

function Get-TextItems {
    param([object]$Value)

    $items = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Value)) {
        if ($null -ne $item -and -not [string]::IsNullOrWhiteSpace([string]$item)) {
            $items.Add(([string]$item).Trim()) | Out-Null
        }
    }
    return $items.ToArray()
}

function Test-TextProperty {
    param(
        [Parameter(Mandatory = $true)][object]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($Object.PSObject.Properties.Name -notcontains $Name) { return $false }
    return -not [string]::IsNullOrWhiteSpace([string]$Object.$Name)
}

function ConvertFrom-IsoDate {
    param([object]$Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }

    $parsed = [datetime]::MinValue
    $ok = [datetime]::TryParseExact(
        [string]$Value,
        "yyyy-MM-dd",
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref]$parsed
    )
    if ($ok) { return $parsed }
    return $null
}

if (-not $ProjectRoot) {
    $ProjectRoot = Join-Path $PSScriptRoot ".."
}
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path

if (-not $RegistryPath) {
    $RegistryPath = Join-Path $root "harness.components.json"
}
if (-not (Test-Path -LiteralPath $RegistryPath -PathType Leaf)) {
    throw "Harness component registry not found: $RegistryPath"
}
$registryFullPath = (Resolve-Path -LiteralPath $RegistryPath).Path

try {
    $registry = Get-Content -LiteralPath $registryFullPath -Raw | ConvertFrom-Json
} catch {
    throw "Harness component registry is not valid JSON: $($_.Exception.Message)"
}

$errors = New-Object System.Collections.Generic.List[object]
$warnings = New-Object System.Collections.Generic.List[object]
$staleReviews = New-Object System.Collections.Generic.List[object]
$staleStatuses = New-Object System.Collections.Generic.List[object]
$retirementCandidates = New-Object System.Collections.Generic.List[object]
$missingReferences = New-Object System.Collections.Generic.List[object]
$duplicateIds = New-Object System.Collections.Generic.List[string]
$allowedTypes = @("hooks", "agents", "skills", "evals", "automations", "mcps", "scripts", "docs")
$defaultStatuses = @("proposed", "experimental", "active", "watch", "deprecated", "retired")
$allowedLevels = @("low", "medium", "high")
$requiredFields = @(
    "id",
    "type",
    "owner",
    "purpose",
    "compensation_hypothesis",
    "paths",
    "evidence",
    "cost",
    "risk",
    "status",
    "status_since",
    "review",
    "retirement_criteria"
)

if ([string]$registry.schema -ne "codex-harness-components-v1") {
    Add-Issue -List $errors -Code "schema" -Detail "schema must be codex-harness-components-v1"
}
if (-not (ConvertFrom-IsoDate -Value $registry.updated_at)) {
    Add-Issue -List $errors -Code "updated-at" -Detail "updated_at must use yyyy-MM-dd"
}

$allowedStatuses = $defaultStatuses
$experimentalMaxDays = 90
$deprecatedGraceDays = 30
if ($registry.PSObject.Properties.Name -contains "review_policy" -and $null -ne $registry.review_policy) {
    $configuredStatuses = @(Get-TextItems -Value $registry.review_policy.allowed_statuses)
    if ($configuredStatuses.Count -gt 0) { $allowedStatuses = $configuredStatuses }
    if ([int]$registry.review_policy.experimental_max_days -gt 0) {
        $experimentalMaxDays = [int]$registry.review_policy.experimental_max_days
    }
    if ([int]$registry.review_policy.deprecated_grace_days -gt 0) {
        $deprecatedGraceDays = [int]$registry.review_policy.deprecated_grace_days
    }
}

$components = @($registry.components)
if ($components.Count -eq 0 -or ($components.Count -eq 1 -and $null -eq $components[0])) {
    Add-Issue -List $errors -Code "components" -Detail "components must contain at least one entry"
    $components = @()
}

$seenIds = @{}
$seenTypes = @{}
foreach ($component in $components) {
    $componentId = if (Test-TextProperty -Object $component -Name "id") { ([string]$component.id).Trim() } else { "" }

    foreach ($field in $requiredFields) {
        if ($component.PSObject.Properties.Name -notcontains $field -or $null -eq $component.$field) {
            Add-Issue -List $errors -Code "required-field" -ComponentId $componentId -Detail "missing required field: $field"
        }
    }

    foreach ($field in @("id", "type", "owner", "purpose", "compensation_hypothesis", "status", "status_since")) {
        if (-not (Test-TextProperty -Object $component -Name $field)) {
            Add-Issue -List $errors -Code "required-text" -ComponentId $componentId -Detail "$field must be non-empty text"
        }
    }

    if ($componentId) {
        if ($seenIds.ContainsKey($componentId)) {
            if ($duplicateIds -notcontains $componentId) { $duplicateIds.Add($componentId) | Out-Null }
            Add-Issue -List $errors -Code "duplicate-id" -ComponentId $componentId -Detail "component ID is duplicated"
        } else {
            $seenIds[$componentId] = $true
        }
    }

    $componentType = ([string]$component.type).Trim().ToLowerInvariant()
    if ($componentType -notin $allowedTypes) {
        Add-Issue -List $errors -Code "component-type" -ComponentId $componentId -Detail "unsupported type: $componentType"
    } else {
        $seenTypes[$componentType] = $true
    }

    $status = ([string]$component.status).Trim().ToLowerInvariant()
    if ($status -notin $allowedStatuses) {
        Add-Issue -List $errors -Code "status" -ComponentId $componentId -Detail "unsupported status: $status"
    }

    $statusSince = ConvertFrom-IsoDate -Value $component.status_since
    if (-not $statusSince) {
        Add-Issue -List $errors -Code "status-date" -ComponentId $componentId -Detail "status_since must use yyyy-MM-dd"
    }

    $paths = @(Get-TextItems -Value $component.paths)
    $evidence = @(Get-TextItems -Value $component.evidence)
    $retirementCriteria = @(Get-TextItems -Value $component.retirement_criteria)
    if ($paths.Count -eq 0) {
        Add-Issue -List $errors -Code "paths" -ComponentId $componentId -Detail "paths must contain at least one referenced path"
    }
    if ($evidence.Count -eq 0) {
        Add-Issue -List $errors -Code "evidence" -ComponentId $componentId -Detail "evidence must contain at least one referenced path"
    }
    if ($retirementCriteria.Count -eq 0) {
        Add-Issue -List $errors -Code "retirement-criteria" -ComponentId $componentId -Detail "retirement_criteria must contain at least one criterion"
    }

    foreach ($reference in @($paths + $evidence)) {
        $resolvedReference = if ([System.IO.Path]::IsPathRooted($reference)) {
            $reference
        } else {
            Join-Path $root ($reference -replace '/', '\')
        }
        if (-not (Test-Path -LiteralPath $resolvedReference)) {
            $missingReferences.Add([pscustomobject]@{
                component_id = $componentId
                reference = $reference
                resolved_path = $resolvedReference
            }) | Out-Null
            Add-Issue -List $errors -Code "missing-reference" -ComponentId $componentId -Detail "referenced path not found: $reference"
        }
    }

    foreach ($dimension in @("cost", "risk")) {
        $value = $component.$dimension
        if ($null -eq $value) { continue }
        $level = ([string]$value.level).Trim().ToLowerInvariant()
        if ($level -notin $allowedLevels) {
            Add-Issue -List $errors -Code "$dimension-level" -ComponentId $componentId -Detail "$dimension.level must be low, medium, or high"
        }
        if (@(Get-TextItems -Value $value.drivers).Count -eq 0) {
            Add-Issue -List $errors -Code "$dimension-drivers" -ComponentId $componentId -Detail "$dimension.drivers must contain at least one item"
        }
    }

    $review = $component.review
    if ($null -ne $review) {
        $cadenceDays = 0
        if (-not [int]::TryParse([string]$review.cadence_days, [ref]$cadenceDays) -or $cadenceDays -le 0) {
            Add-Issue -List $errors -Code "review-cadence" -ComponentId $componentId -Detail "review.cadence_days must be a positive integer"
        }
        $lastReviewed = ConvertFrom-IsoDate -Value $review.last_reviewed
        if (-not $lastReviewed) {
            Add-Issue -List $errors -Code "review-date" -ComponentId $componentId -Detail "review.last_reviewed must use yyyy-MM-dd"
        } elseif ($cadenceDays -gt 0 -and $AsOfDate.Date -gt $lastReviewed.AddDays($cadenceDays)) {
            $item = [pscustomobject]@{
                component_id = $componentId
                last_reviewed = $lastReviewed.ToString("yyyy-MM-dd")
                cadence_days = $cadenceDays
                due_date = $lastReviewed.AddDays($cadenceDays).ToString("yyyy-MM-dd")
            }
            $staleReviews.Add($item) | Out-Null
            Add-Issue -List $warnings -Code "stale-review" -ComponentId $componentId -Detail "review was due on $($item.due_date)"
        }
    }

    if ($statusSince) {
        $statusAgeDays = [int][Math]::Floor(($AsOfDate.Date - $statusSince.Date).TotalDays)
        if ($status -eq "experimental" -and $statusAgeDays -gt $experimentalMaxDays) {
            $staleStatuses.Add([pscustomobject]@{
                component_id = $componentId
                status = $status
                status_since = $statusSince.ToString("yyyy-MM-dd")
                age_days = $statusAgeDays
            }) | Out-Null
            Add-Issue -List $warnings -Code "stale-status" -ComponentId $componentId -Detail "experimental status exceeds $experimentalMaxDays days"
        }
        if ($status -eq "deprecated" -and $statusAgeDays -gt $deprecatedGraceDays) {
            $staleStatuses.Add([pscustomobject]@{
                component_id = $componentId
                status = $status
                status_since = $statusSince.ToString("yyyy-MM-dd")
                age_days = $statusAgeDays
            }) | Out-Null
            Add-Issue -List $warnings -Code "stale-status" -ComponentId $componentId -Detail "deprecated status exceeds $deprecatedGraceDays days"
        }
    }

    if ($status -in @("deprecated", "retired")) {
        $retirementCandidates.Add([pscustomobject]@{
            component_id = $componentId
            status = $status
            criteria = $retirementCriteria
        }) | Out-Null
        Add-Issue -List $warnings -Code "retirement-candidate" -ComponentId $componentId -Detail "status requires an explicit retirement review"
    }
}

foreach ($requiredType in $allowedTypes) {
    if (-not $seenTypes.ContainsKey($requiredType)) {
        Add-Issue -List $errors -Code "missing-component-type" -Detail "registry has no component of type: $requiredType"
    }
}

$typeCounts = [ordered]@{}
foreach ($type in $allowedTypes) {
    $typeCounts[$type] = @($components | Where-Object { ([string]$_.type).ToLowerInvariant() -eq $type }).Count
}

$statusResult = if ($errors.Count -gt 0) {
    "failed"
} elseif ($warnings.Count -gt 0) {
    "warning"
} else {
    "passed"
}

$report = [ordered]@{
    schema = "codex-harness-component-audit-v1"
    status = $statusResult
    created_at = (Get-Date).ToString("o")
    as_of = $AsOfDate.ToString("yyyy-MM-dd")
    read_only = $true
    project_root = $root
    registry_path = $registryFullPath
    component_count = $components.Count
    type_counts = $typeCounts
    errors = $errors.ToArray()
    warnings = $warnings.ToArray()
    duplicate_ids = $duplicateIds.ToArray()
    missing_references = $missingReferences.ToArray()
    stale_reviews = $staleReviews.ToArray()
    stale_statuses = $staleStatuses.ToArray()
    retirement_candidates = $retirementCandidates.ToArray()
}

$report | ConvertTo-Json -Depth 12 -Compress

if ($statusResult -eq "failed") {
    throw "Harness component audit failed with $($errors.Count) error(s)."
}
if ($FailOnWarnings -and $warnings.Count -gt 0) {
    throw "Harness component audit found $($warnings.Count) warning(s)."
}
