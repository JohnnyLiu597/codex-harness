param(
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$BaseRef = "HEAD~1"
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportDir = Join-Path $root ("artifacts\docs-sync\" + $stamp)
$jsonPath = Join-Path $reportDir "docs-sync.json"
$summaryPath = Join-Path $reportDir "summary.md"

New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

$branch = ""
$head = ""
$committedChanges = @()
$dirtyChanges = @()

try { $branch = (git -C $root branch --show-current 2>$null) } catch {}
try { $head = (git -C $root rev-parse --short HEAD 2>$null) } catch {}

try {
    git -C $root rev-parse --verify $BaseRef 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $committedChanges = @(git -C $root diff --name-status $BaseRef HEAD 2>$null)
    }
} catch {}

try {
    $dirtyChanges = @(git -C $root status --porcelain=v1 2>$null)
} catch {}

$projectDoc = Join-Path $root "docs\project.md"
$docFiles = @(
    "docs/project.md",
    "docs/architecture.md",
    "docs/commands.md",
    "docs/testing.md",
    "docs/smoke.md",
    "mission.md",
    "CONTEXT.md",
    "MEMORY.md"
)

function Get-PathFromStatusLine {
    param([string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line) -or $Line.Length -lt 4) { return "" }
    $path = $Line.Substring(3)
    if ($path -match ' -> ') { return (($path -split ' -> ')[-1]).Replace('\', '/') }
    return $path.Replace('\', '/')
}

$allChangedPaths = New-Object System.Collections.Generic.List[string]
foreach ($line in $committedChanges) {
    $parts = $line -split "`t"
    if ($parts.Count -gt 1) { $allChangedPaths.Add($parts[-1].Replace('\', '/')) | Out-Null }
}
foreach ($line in $dirtyChanges) {
    $p = Get-PathFromStatusLine -Line $line
    if ($p) { $allChangedPaths.Add($p) | Out-Null }
}

$runtimeChanged = @($allChangedPaths | Where-Object {
    $_ -match '^(src|app|lib|packages|crates|src-tauri|server|backend|frontend|components|pages|api)/' -or
    $_ -match '^(package\.json|package-lock\.json|pnpm-lock\.yaml|yarn\.lock|Cargo\.toml|Cargo\.lock|pyproject\.toml|requirements\.txt|vite\.config|next\.config|tauri\.conf)'
})

$docsChanged = @($allChangedPaths | Where-Object { $docFiles -contains $_ })
$status = "passed"
$notes = New-Object System.Collections.Generic.List[string]

if (-not (Test-Path -LiteralPath $projectDoc)) {
    $status = "warning"
    $notes.Add("docs/project.md is missing.") | Out-Null
}

if ($runtimeChanged.Count -gt 0 -and $docsChanged.Count -eq 0) {
    $status = "warning"
    $notes.Add("Runtime or project behavior changed, but no project docs changed.") | Out-Null
}

if ($notes.Count -eq 0) {
    $notes.Add("Project docs appear synchronized for the current diff scope.") | Out-Null
}

$record = [pscustomobject]@{
    schema = "project-docs-sync-v1"
    status = $status
    created_at = (Get-Date).ToString("o")
    root = $root
    branch = $branch
    head = $head
    base_ref = $BaseRef
    docs_present = Test-Path -LiteralPath $projectDoc
    runtime_changed = @($runtimeChanged)
    docs_changed = @($docsChanged)
    dirty_changes = @($dirtyChanges)
    committed_changes = @($committedChanges)
    notes = $notes.ToArray()
}

$record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$noteLines = ($notes | ForEach-Object { "- $_" }) -join "`r`n"
$runtimeLines = if ($runtimeChanged.Count -gt 0) { ($runtimeChanged | ForEach-Object { "- $_" }) -join "`r`n" } else { "- None detected." }
$docLines = if ($docsChanged.Count -gt 0) { ($docsChanged | ForEach-Object { "- $_" }) -join "`r`n" } else { "- None detected." }

$md = @"
# Project Docs Sync

- Status: $status
- Created: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
- Branch: $branch
- HEAD: $head
- Base ref: $BaseRef

## Notes

$noteLines

## Runtime Or Behavior Changes

$runtimeLines

## Documentation Changes

$docLines

## Artifacts

- docs-sync.json
"@

Set-Content -LiteralPath $summaryPath -Value $md -Encoding UTF8

[ordered]@{
    status = $status
    summary = "Project docs sync check completed."
    branch = $branch
    head = $head
    artifacts = @($jsonPath, $summaryPath)
} | ConvertTo-Json -Depth 5 -Compress
