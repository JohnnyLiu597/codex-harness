param(
    [switch]$WriteReport
)

$ErrorActionPreference = "Stop"

$globalScript = "$env:USERPROFILE\.codex\scripts\audit-project-harness.ps1"
if (-not (Test-Path -LiteralPath $globalScript)) {
    throw "Global audit-project-harness.ps1 not found: $globalScript"
}

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
& $globalScript -ProjectRoot $root -WriteReport:$WriteReport
