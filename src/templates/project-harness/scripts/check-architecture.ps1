param(
    [switch]$Strict,
    [switch]$ChangedOnly,
    [string]$BaseRef = "HEAD"
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$warnings = New-Object System.Collections.Generic.List[string]
$failures = New-Object System.Collections.Generic.List[string]
$changedPaths = @()

try {
    if (Test-Path -LiteralPath (Join-Path $root ".git")) {
        $changedPaths = @(git -C $root status --short | ForEach-Object {
            $p = $_.Substring(3).Trim()
            if ($p -match " -> ") { $p = ($p -split " -> ")[-1] }
            $p -replace '/', '\'
        })
    }
} catch { $changedPaths = @() }

function Should-Inspect {
    param([Parameter(Mandatory = $true)][string]$Rel)
    if (-not $ChangedOnly) { return $true }
    $normalized = $Rel -replace '/', '\'
    foreach ($changed in $changedPaths) {
        if ($changed -ieq $normalized -or $changed.StartsWith($normalized + "\", [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

foreach ($rel in @("docs\architecture.md", "docs\code-map.md", "docs\features.json")) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $rel))) {
        $failures.Add("Missing architecture harness path: $rel") | Out-Null
    }
}

foreach ($dir in @("src", "app", "lib", "packages", "crates", "server", "backend", "frontend")) {
    $path = Join-Path $root $dir
    if (Test-Path -LiteralPath $path) {
        Get-ChildItem -LiteralPath $path -Recurse -File -Include *.ts,*.tsx,*.js,*.jsx,*.rs,*.py,*.go -ErrorAction SilentlyContinue |
            ForEach-Object {
                $relPath = $_.FullName
                if ($relPath.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $relPath = $relPath.Substring($root.Length).TrimStart('\', '/')
                }
                if (-not (Should-Inspect -Rel $relPath)) { return }
                $lines = (Get-Content -LiteralPath $_.FullName -ErrorAction SilentlyContinue).Count
                if ($lines -gt 2500) {
                    $warnings.Add("$relPath is $lines lines; prefer small isolated changes and focused verification.") | Out-Null
                }
            }
    }
}

$dangerousHarness = @()
foreach ($rel in @("scripts", "docs", "AGENTS.md", ".codex")) {
    $path = Join-Path $root $rel
    if (Test-Path -LiteralPath $path) {
        $files = if ((Get-Item -LiteralPath $path).PSIsContainer) { Get-ChildItem -LiteralPath $path -Recurse -File -ErrorAction SilentlyContinue } else { @(Get-Item -LiteralPath $path) }
        if ($ChangedOnly) {
            $files = @($files | Where-Object {
                $relPath = $_.FullName
                if ($relPath.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) { $relPath = $relPath.Substring($root.Length).TrimStart('\', '/') }
                $changedPaths -contains ($relPath -replace '/', '\')
            })
        }
        $matches = $files | Select-String -Pattern "Remove-Item\s+-Recurse", "rm\s+-rf", "git\s+clean" -ErrorAction SilentlyContinue
        foreach ($m in $matches) {
            if ($m.Path -ieq $PSCommandPath) { continue }
            if ($m.Path -match "\\artifacts\\checks\\|\\artifacts\\worktree-audits\\|\\node_modules\\") { continue }
            if ($m.Line -match "Do not|unless|destructive|Permanent deletion|template|placeholder") { continue }
            $dangerousHarness += "$($m.Path):$($m.LineNumber)"
        }
    }
}
if ($dangerousHarness.Count -gt 0) { $failures.Add("Dangerous cleanup commands found in harness files: $($dangerousHarness -join ', ')") | Out-Null }
if ($Strict -and $warnings.Count -gt 0) { foreach ($warning in $warnings) { $failures.Add($warning) | Out-Null } }

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runDir = Join-Path $root ("artifacts\architecture-checks\" + $stamp)
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$jsonPath = Join-Path $runDir "architecture-check.json"
$summaryPath = Join-Path $runDir "summary.md"
$status = if ($failures.Count -gt 0) { "failed" } else { "passed" }

[ordered]@{
    schema = "architecture-check-v1"
    status = $status
    created_at = (Get-Date).ToString("o")
    root = $root
    strict = [bool]$Strict
    changed_only = [bool]$ChangedOnly
    changed_paths = $changedPaths
    warnings = $warnings.ToArray()
    failures = $failures.ToArray()
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$warningLines = if ($warnings.Count -gt 0) { ($warnings | ForEach-Object { "- $_" }) -join "`r`n" } else { "- None." }
$failureLines = if ($failures.Count -gt 0) { ($failures | ForEach-Object { "- $_" }) -join "`r`n" } else { "- None." }
$md = @"
# Architecture Check

- Status: $status
- Strict: $([bool]$Strict)
- Changed only: $([bool]$ChangedOnly)

## Warnings

$warningLines

## Failures

$failureLines
"@
Set-Content -LiteralPath $summaryPath -Value $md -Encoding UTF8
if ($failures.Count -gt 0) { throw "Architecture check failed. See $summaryPath" }

[ordered]@{ status = "success"; summary = "Architecture check completed."; warnings = $warnings.ToArray(); changed_only = [bool]$ChangedOnly; artifacts = @($jsonPath, $summaryPath) } | ConvertTo-Json -Depth 6 -Compress
