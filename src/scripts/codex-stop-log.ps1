param()

$ErrorActionPreference = "SilentlyContinue"

$payload = ""
try {
    $payload = [Console]::In.ReadToEnd()
} catch {
    $payload = ""
}

$router = Join-Path $PSScriptRoot "codex-hook-router.ps1"
if (Test-Path -LiteralPath $router) {
    & $router -Event Stop -Payload $payload -Quiet
    exit 0
}

$logRoot = "$env:USERPROFILE\.codex\hook-logs"
if (-not (Test-Path -LiteralPath $logRoot)) {
    New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
}

$timestamp = (Get-Date).ToUniversalTime().ToString("o")
$latestPath = Join-Path $logRoot "latest-stop.txt"
Set-Content -LiteralPath $latestPath -Value "Last Codex Stop hook: $timestamp`nSummary: Task completed." -Encoding UTF8
exit 0
