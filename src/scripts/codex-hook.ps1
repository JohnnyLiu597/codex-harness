param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("SessionStart", "SessionEnd", "PreToolUse", "PermissionRequest", "PostToolUse", "PreCompact", "PostCompact", "UserPromptSubmit", "SubagentStart", "SubagentStop", "Stop")]
    [string]$Event
)

$ErrorActionPreference = "SilentlyContinue"

$payload = ""
try {
    [Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false)
    $payload = [Console]::In.ReadToEnd()
    if ($payload.Length -gt 0 -and [int][char]$payload[0] -eq 0xfeff) {
        $payload = $payload.Substring(1)
    }
} catch {
    $payload = ""
}

$codexHomePath = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$activeWeeklyRun = $false
if ($Event -in @('PreToolUse', 'PermissionRequest')) {
    $activeRunPath = Join-Path $codexHomePath 'harness-learning\active-run.json'
    if (Test-Path -LiteralPath $activeRunPath -PathType Leaf) {
        try {
            $payloadJson = $payload | ConvertFrom-Json
            $activeRun = Get-Content -LiteralPath $activeRunPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $boundSessionKey = [string]$activeRun.session_key
            if ([string]::IsNullOrWhiteSpace($boundSessionKey)) {
                $activeWeeklyRun = $true
            } elseif ($payloadJson.session_id) {
                $sha = [System.Security.Cryptography.SHA256]::Create()
                try {
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$payloadJson.session_id)
                    $sessionKey = ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant().Substring(0, 24)
                    $activeWeeklyRun = $sessionKey -eq $boundSessionKey
                } finally {
                    $sha.Dispose()
                }
            }
        } catch {
            $activeWeeklyRun = $true
        }
    }
    if (-not $activeWeeklyRun) {
        $toolName = ''
        try { $toolName = [string](($payload | ConvertFrom-Json).tool_name) } catch { }
        if ($toolName -notin @('Bash', 'apply_patch', 'Edit', 'Write')) {
            exit 0
        }
    }
}

function Write-RestrictedDeny {
    param([string]$HookEventName)

    $reason = 'Weekly harness learning is in restricted mode, but its policy router is unavailable. Stop this run and inspect the local hook installation.'
    $output = if ($HookEventName -eq 'PermissionRequest') {
        [ordered]@{
            systemMessage = $reason
            hookSpecificOutput = [ordered]@{
                hookEventName = 'PermissionRequest'
                decision = [ordered]@{ behavior = 'deny'; message = $reason }
            }
        }
    } else {
        [ordered]@{
            systemMessage = $reason
            hookSpecificOutput = [ordered]@{
                hookEventName = 'PreToolUse'
                permissionDecision = 'deny'
                permissionDecisionReason = $reason
            }
        }
    }
    [Console]::Out.WriteLine(($output | ConvertTo-Json -Depth 6 -Compress))
}

$router = Join-Path $PSScriptRoot "codex-hook-router.ps1"
if (-not (Test-Path -LiteralPath $router -PathType Leaf)) {
    if ($activeWeeklyRun -and $Event -in @('PreToolUse', 'PermissionRequest')) {
        Write-RestrictedDeny -HookEventName $Event
    }
    exit 0
}

$routerFailed = $false
try {
    & $router -Event $Event -Payload $payload -Quiet
    if (-not $?) { $routerFailed = $true }
} catch {
    $routerFailed = $true
}
if ($routerFailed -and $activeWeeklyRun -and $Event -in @('PreToolUse', 'PermissionRequest')) {
    Write-RestrictedDeny -HookEventName $Event
}
exit 0
