param(
    [string]$BaseRef = "HEAD~1"
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$codexHome = Join-Path $env:USERPROFILE ".codex"
$script = Join-Path $codexHome "scripts\check-project-docs.ps1"
if (-not (Test-Path -LiteralPath $script)) {
    throw "Global check-project-docs.ps1 not found: $script"
}
& $script -ProjectRoot $root -BaseRef $BaseRef
