param(
    [ValidateSet("plan", "verify", "tdd", "e2e", "review", "security", "learn", "checkpoint", "orchestrate")]
    [string]$Workflow = "verify",
    [string]$Task = "",
    [switch]$Run,
    [switch]$ContinueOnError
)

$ErrorActionPreference = "Stop"

$codexHome = Join-Path $env:USERPROFILE ".codex"
$script = Join-Path $codexHome "scripts\invoke-codex-workflow.ps1"
if (-not (Test-Path -LiteralPath $script)) {
    throw "Global invoke-codex-workflow.ps1 not found: $script"
}

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
& $script -ProjectRoot $root -Workflow $Workflow -Task $Task -Run:$Run -ContinueOnError:$ContinueOnError
