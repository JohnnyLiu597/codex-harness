param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Prompt,
    [string]$Expected = "",
    [string[]]$MustInclude = @(),
    [string[]]$MustNotInclude = @(),
    [string]$Lane = "regression",
    [int]$MinScore = 75,
    [switch]$Disabled
)

$ErrorActionPreference = "Stop"

$globalScript = "C:\Users\Johnny Liu\.codex\scripts\new-trace-eval.ps1"
if (-not (Test-Path -LiteralPath $globalScript)) {
    throw "Global new-trace-eval.ps1 not found: $globalScript"
}

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
& $globalScript -Root $root -Name $Name -Prompt $Prompt -Expected $Expected -MustInclude $MustInclude -MustNotInclude $MustNotInclude -Lane $Lane -MinScore $MinScore -Disabled:$Disabled
