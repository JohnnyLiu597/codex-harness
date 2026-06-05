param(
    [switch]$Markdown
)

$ErrorActionPreference = "Stop"

$codexHome = Join-Path $env:USERPROFILE ".codex"
$script = Join-Path $codexHome "scripts\detect-project-test-surface.ps1"
if (-not (Test-Path -LiteralPath $script)) {
    throw "Global detect-project-test-surface.ps1 not found: $script"
}

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
& $script -ProjectRoot $root -Markdown:$Markdown
