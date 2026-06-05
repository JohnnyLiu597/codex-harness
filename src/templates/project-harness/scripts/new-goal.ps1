param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Objective,
    [string]$Status = "active",
    [string]$Horizon = "long-running",
    [string[]]$SuccessCriteria = @(),
    [string[]]$FeatureIds = @(),
    [string[]]$Notes = @(),
    [switch]$SetCurrent
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$slug = ($Name -replace '[^a-zA-Z0-9]+', '-').Trim('-').ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($slug)) {
    $slug = "goal"
}

$goalDir = Join-Path $root ("artifacts\goals\" + $stamp + "-" + $slug)
New-Item -ItemType Directory -Force -Path $goalDir | Out-Null

$branch = ""
$head = ""
try {
    $branch = (git -C $root branch --show-current 2>$null | Out-String).Trim()
    $head = (git -C $root rev-parse --short HEAD 2>$null | Out-String).Trim()
} catch {
    $branch = "unknown"
    $head = "unknown"
}

$record = [ordered]@{
    schema = "codex-goal-v1"
    name = $Name
    slug = $slug
    objective = $Objective
    status = $Status
    horizon = $Horizon
    created_at = (Get-Date).ToString("o")
    root = $root
    branch = $branch
    head = $head
    success_criteria = $SuccessCriteria
    feature_ids = $FeatureIds
    notes = $Notes
}

$jsonPath = Join-Path $goalDir "goal.json"
$mdPath = Join-Path $goalDir "goal.md"
$record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

function Format-Lines {
    param([string[]]$Lines, [string]$Empty = "- Not recorded yet.")
    if ($Lines.Count -eq 0) { return $Empty }
    return (($Lines | ForEach-Object { "- $_" }) -join "`r`n")
}

$md = @"
# Goal: $Name

- Status: $Status
- Horizon: $Horizon
- Branch: $branch
- Head: $head
- Created: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))

## Objective

$Objective

## Success Criteria

$(Format-Lines -Lines $SuccessCriteria)

## Linked Feature IDs

$(Format-Lines -Lines $FeatureIds)

## Notes

$(Format-Lines -Lines $Notes)

## Codex Session Goal

When the Codex experimental goals feature is enabled and the active UI supports
it, mirror the active objective with:

~~~text
/goal $Objective
~~~

If Codex Desktop sends `/goal ...` as plain chat text instead of showing a
target icon, treat it as an explicit goal request and keep this file as the
durable goal record.
"@

Set-Content -LiteralPath $mdPath -Value $md -Encoding UTF8

$currentPath = ""
if ($SetCurrent) {
    $currentPath = Join-Path $root "artifacts\goals\current.md"
    Set-Content -LiteralPath $currentPath -Value "Current goal: $Name`r`n`r`nSee: $mdPath`r`n" -Encoding UTF8
}

[ordered]@{
    status = "success"
    summary = "Created goal record."
    artifacts = @($jsonPath, $mdPath, $currentPath) | Where-Object { $_ }
} | ConvertTo-Json -Depth 5 -Compress
