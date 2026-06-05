param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

$ErrorActionPreference = "Stop"

$codexHome = Join-Path $env:USERPROFILE ".codex"
$script = Join-Path $codexHome "scripts\safe-remove.ps1"
if (-not (Test-Path -LiteralPath $script)) {
    throw "Global safe-remove.ps1 not found: $script"
}
& $script @Args
