param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("SessionStart", "SessionEnd", "PreToolUse", "PermissionRequest", "PostToolUse", "PreCompact", "PostCompact", "UserPromptSubmit", "SubagentStart", "SubagentStop", "Stop")]
    [string]$Event
)

$ErrorActionPreference = "SilentlyContinue"

$payload = ""
try {
    $payload = [Console]::In.ReadToEnd()
} catch {
    $payload = ""
}

$router = Join-Path $PSScriptRoot "codex-hook-router.ps1"
if (-not (Test-Path -LiteralPath $router -PathType Leaf)) {
    exit 0
}

& $router -Event $Event -Payload $payload -Quiet
exit 0
