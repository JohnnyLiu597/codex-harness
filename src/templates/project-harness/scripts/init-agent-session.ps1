param(
    [switch]$Json
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$branch = ""
$head = ""
$dirty = @()
$nextFeatures = @()

try {
    $branch = (git -C $root branch --show-current 2>$null | Out-String).Trim()
    $head = (git -C $root rev-parse --short HEAD 2>$null | Out-String).Trim()
    $dirty = @(git -C $root status --short 2>$null)
} catch {
    $branch = "unknown"
    $head = "unknown"
}

$featurePath = Join-Path $root "docs\features.json"
if (Test-Path -LiteralPath $featurePath) {
    $features = (Get-Content -LiteralPath $featurePath -Raw | ConvertFrom-Json).features
    $nextFeatures = @(
        $features |
            Where-Object { $_.passes -ne $true } |
            Sort-Object @{ Expression = {
                switch ($_.priority) {
                    "critical" { 0 }
                    "high" { 1 }
                    "medium" { 2 }
                    default { 3 }
                }
            }}, id |
            Select-Object -First 5 id, category, priority, status, description
    )
}

$recommended = @(
    "Read AGENTS.md, CONTEXT.md, MEMORY.md, docs/project.md, docs/code-map.md, and docs/features.json.",
    "Run scripts/audit-worktree.ps1 before touching business code in this dirty repo.",
    "Run scripts/check-all.ps1 for harness-only changes.",
    "Use scripts/check-all.ps1 -Runtime or -Smoke when app behavior changes."
)

$record = [ordered]@{
    schema = "agent-session-init-v1"
    root = $root
    branch = $branch
    head = $head
    dirty_count = $dirty.Count
    dirty_sample = @($dirty | Select-Object -First 20)
    next_features = $nextFeatures
    recommended_start = $recommended
}

if ($Json) {
    $record | ConvertTo-Json -Depth 8 -Compress
    exit 0
}

Write-Output "# Agent Session Init"
Write-Output ""
Write-Output "- Root: $root"
Write-Output "- Branch: $branch"
Write-Output "- Head: $head"
Write-Output "- Dirty entries: $($dirty.Count)"
Write-Output ""
Write-Output "## Recommended Start"
foreach ($item in $recommended) {
    Write-Output "- $item"
}
Write-Output ""
Write-Output "## Next Feature Candidates"
if ($nextFeatures.Count -eq 0) {
    Write-Output "- No open feature entries found."
} else {
    foreach ($feature in $nextFeatures) {
        Write-Output "- $($feature.id) [$($feature.priority)] $($feature.description)"
    }
}
