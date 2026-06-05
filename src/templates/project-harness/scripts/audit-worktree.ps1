param(
    [switch]$NoReport
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$auditDir = Join-Path $root ("artifacts\worktree-audits\" + $stamp)
$jsonPath = Join-Path $auditDir "worktree-audit.json"
$summaryPath = Join-Path $auditDir "summary.md"

function Get-Category {
    param([Parameter(Mandatory = $true)][string]$Path)
    $p = $Path.Replace("\", "/")
    if ($p -match '^(\.codex/|AGENTS\.md$|mission\.md$|CONTEXT\.md$|MEMORY\.md$|docs/|scripts/|artifacts/)') { return "harness" }
    if ($p -match '^(test|tests|spec|__tests__|e2e)/') { return "tests" }
    if ($p -match '^(src|app|lib|packages|crates|server|backend|frontend|components|pages|api)/') { return "product-code" }
    if ($p -match '^(package\.json|package-lock\.json|pnpm-lock\.yaml|yarn\.lock|Cargo\.toml|Cargo\.lock|pyproject\.toml|requirements\.txt|vite\.config|next\.config|tsconfig|eslint\.config)') { return "build-tooling" }
    return "other"
}

function Get-Risk {
    param([string]$Category, [string]$Status)
    if ($Status -match 'D') { return "high" }
    if ($Category -in @("product-code", "build-tooling")) { return "medium" }
    return "low"
}

$statusLines = @()
try { $statusLines = @(git -C $root status --porcelain=v1 2>$null) } catch { $statusLines = @() }
$items = New-Object System.Collections.Generic.List[object]

foreach ($line in $statusLines) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 4) { continue }
    $status = $line.Substring(0, 2)
    $path = $line.Substring(3)
    if ($path -match ' -> ') { $path = ($path -split ' -> ')[-1] }
    $category = Get-Category -Path $path
    $items.Add([pscustomobject]@{
        status = $status.Trim()
        path = $path
        category = $category
        risk = Get-Risk -Category $category -Status $status
    }) | Out-Null
}

$groups = @($items | Group-Object category | Sort-Object Name | ForEach-Object {
    [pscustomobject]@{
        category = $_.Name
        count = $_.Count
        high_risk_count = @($_.Group | Where-Object { $_.risk -eq "high" }).Count
        files = @($_.Group | ForEach-Object { $_.path })
    }
})

$record = [ordered]@{
    schema = "worktree-audit-v1"
    created_at = (Get-Date).ToString("o")
    root = $root
    total_changes = $items.Count
    groups = $groups
    items = $items.ToArray()
    notes = @("Treat existing dirty changes as user or previous-session work unless proven otherwise.")
}

if (-not $NoReport) {
    New-Item -ItemType Directory -Force -Path $auditDir | Out-Null
    $record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    $groupLines = if ($groups.Count -gt 0) { ($groups | ForEach-Object { "- $($_.category): $($_.count) files, high risk $($_.high_risk_count)" }) -join "`r`n" } else { "- Worktree clean." }
    $itemLines = if ($items.Count -gt 0) { ($items | ForEach-Object { "- [$($_.risk)] $($_.category): $($_.status) $($_.path)" }) -join "`r`n" } else { "- Worktree clean." }
    $md = @"
# Worktree Audit

- Created: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
- Root: $root
- Total changes: $($items.Count)

## Groups

$groupLines

## Files

$itemLines
"@
    Set-Content -LiteralPath $summaryPath -Value $md -Encoding UTF8
}

$record | ConvertTo-Json -Depth 10 -Compress
