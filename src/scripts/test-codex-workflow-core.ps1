param(
    [string]$CodexHome = "$env:USERPROFILE\.codex"
)

$ErrorActionPreference = "Stop"

$codexHomePath = (Resolve-Path -LiteralPath $CodexHome).Path
$checks = New-Object System.Collections.Generic.List[object]

function Add-Check {
    param([string]$Name, [string]$Status, [string]$Detail = "")

    $checks.Add([pscustomobject]@{
        name = $Name
        status = $Status
        detail = $Detail
    }) | Out-Null
}

function Assert-Path {
    param([string]$RelativePath)

    $path = Join-Path $codexHomePath $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing required workflow core path: $RelativePath"
    }
    Add-Check -Name "path:$RelativePath" -Status "passed" -Detail "present"
}

foreach ($relative in @(
    "hooks.json",
    "scripts\codex-hook.ps1",
    "scripts\codex-hook-router.ps1",
    "scripts\detect-project-test-surface.ps1",
    "scripts\invoke-codex-workflow.ps1",
    "scripts\invoke-verification-envelope.ps1",
    "scripts\test-codex-workflow-core.ps1"
)) {
    Assert-Path -RelativePath $relative
}

$hooks = Get-Content -LiteralPath (Join-Path $codexHomePath "hooks.json") -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($eventName in @("SessionStart", "PreToolUse", "PermissionRequest", "PostToolUse", "PreCompact", "PostCompact", "UserPromptSubmit", "SubagentStart", "SubagentStop", "Stop", "SessionEnd")) {
    if ($hooks.hooks.PSObject.Properties.Name -notcontains $eventName) {
        throw "hooks.json is missing $eventName"
    }
}
Add-Check -Name "hooks-json" -Status "passed" -Detail "official lifecycle events configured"

foreach ($eventName in @("PreCompact", "PostCompact")) {
    foreach ($group in @($hooks.hooks.$eventName)) {
        foreach ($hook in @($group.hooks)) {
            if ($hook.PSObject.Properties.Name -contains "additionalContextLimit") {
                throw "$eventName cannot declare additionalContextLimit in this Codex hook contract"
            }
        }
    }
}
Add-Check -Name "hook-context-contract" -Status "passed" -Detail "compact hooks avoid unsupported additional-context fields"

$tmpRoot = Join-Path $env:TEMP ("codex-workflow-core-test-" + [guid]::NewGuid().ToString("N"))
$tmpLogs = Join-Path $tmpRoot "hook-logs"
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null

try {
    $packageJson = @'
{
  "scripts": {
    "build": "echo build-ok",
    "typecheck": "echo types-ok",
    "lint": "echo lint-ok",
    "test": "echo test-ok",
    "e2e": "echo e2e-ok"
  }
}
'@
    Set-Content -LiteralPath (Join-Path $tmpRoot "package.json") -Value $packageJson -Encoding UTF8

    $detect = Join-Path $codexHomePath "scripts\detect-project-test-surface.ps1"
    $surface = (& $detect -ProjectRoot $tmpRoot) | ConvertFrom-Json
    $kinds = @($surface.commands | ForEach-Object { $_.kind })
    foreach ($kind in @("build", "typecheck", "lint", "unit-test", "e2e")) {
        if ($kinds -notcontains $kind) {
            throw "detect-project-test-surface did not detect $kind"
        }
    }
    Add-Check -Name "detect-project-test-surface" -Status "passed" -Detail "detected build/type/lint/test/e2e"

    $workflow = Join-Path $codexHomePath "scripts\invoke-codex-workflow.ps1"
    $workflowOutput = (& $workflow -ProjectRoot $tmpRoot -Workflow verify -Task "self-test") | ConvertFrom-Json
    if ($workflowOutput.status -ne "success") { throw "invoke-codex-workflow failed" }
    Add-Check -Name "invoke-codex-workflow" -Status "passed" -Detail "verify workflow record created"

    $router = Join-Path $codexHomePath "scripts\codex-hook-router.ps1"
    $sessionId = "workflow-core-self-test"
    $secret = "sk-abcdefghijklmnopqrstuvwxyz1234567890"

    $privacyPayload = [ordered]@{
        session_id = $sessionId
        cwd = $tmpRoot
        hook_event_name = "PostToolUse"
        message = "raw message must not persist"
        summary = "raw summary must not persist"
        prompt = "prompt $secret"
        tool_name = "Bash"
        tool_input = @{ command = "Write-Output '$secret'" }
        tool_response = @{ exit_code = 0; output = "response $secret" }
    } | ConvertTo-Json -Depth 10 -Compress
    & $router -Event PostToolUse -Payload $privacyPayload -LogRoot $tmpLogs -Quiet | Out-Null

    $dangerPayload = [ordered]@{
        session_id = $sessionId
        cwd = $tmpRoot
        hook_event_name = "PreToolUse"
        tool_name = "Bash"
        tool_input = @{ command = "git reset --hard HEAD" }
    } | ConvertTo-Json -Depth 8 -Compress
    $danger = ((& $router -Event PreToolUse -Payload $dangerPayload -LogRoot $tmpLogs -Quiet) -join "") | ConvertFrom-Json
    if ($danger.hookSpecificOutput.permissionDecision -ne "deny") {
        throw "PreToolUse did not deny a high-confidence destructive command"
    }
    Add-Check -Name "hook-destructive-guard" -Status "passed" -Detail "PreToolUse returned an official deny decision"

    $promptPayload = [ordered]@{
        session_id = $sessionId
        cwd = $tmpRoot
        hook_event_name = "UserPromptSubmit"
        prompt = "credential $secret"
    } | ConvertTo-Json -Depth 8 -Compress
    $promptDecision = ((& $router -Event UserPromptSubmit -Payload $promptPayload -LogRoot $tmpLogs -Quiet) -join "") | ConvertFrom-Json
    if ($promptDecision.decision -ne "block") {
        throw "UserPromptSubmit did not block a high-confidence credential-like prompt"
    }
    Add-Check -Name "hook-prompt-secret-guard" -Status "passed" -Detail "credential-like prompt blocked without logging its value"

    $editPayload = [ordered]@{
        session_id = $sessionId
        cwd = $tmpRoot
        hook_event_name = "PostToolUse"
        tool_name = "apply_patch"
        tool_input = @{ command = "private patch body $secret" }
        tool_response = @{ isError = $false }
    } | ConvertTo-Json -Depth 8 -Compress
    & $router -Event PostToolUse -Payload $editPayload -LogRoot $tmpLogs -Quiet | Out-Null

    $failedVerifyPayload = [ordered]@{
        session_id = $sessionId
        cwd = $tmpRoot
        hook_event_name = "PostToolUse"
        tool_name = "Bash"
        tool_input = @{ command = "powershell -File .\verify.ps1" }
        tool_response = @{ exit_code = 1 }
    } | ConvertTo-Json -Depth 8 -Compress
    & $router -Event PostToolUse -Payload $failedVerifyPayload -LogRoot $tmpLogs -Quiet | Out-Null

    $stopPayload = [ordered]@{
        session_id = $sessionId
        cwd = $tmpRoot
        hook_event_name = "Stop"
        stop_hook_active = $false
        last_assistant_message = "done"
    } | ConvertTo-Json -Depth 8 -Compress
    $stopDecision = ((& $router -Event Stop -Payload $stopPayload -LogRoot $tmpLogs -Quiet) -join "") | ConvertFrom-Json
    if ($stopDecision.decision -ne "block") {
        throw "Stop did not request one bounded verification continuation after an edit"
    }

    $continuedStopPayload = [ordered]@{
        session_id = $sessionId
        cwd = $tmpRoot
        hook_event_name = "Stop"
        stop_hook_active = $true
        last_assistant_message = "verification blocker reported"
    } | ConvertTo-Json -Depth 8 -Compress
    $continuedStopRaw = ((& $router -Event Stop -Payload $continuedStopPayload -LogRoot $tmpLogs -Quiet) -join "")
    if ($continuedStopRaw.Trim() -ne "{}") {
        throw "Stop continuation was not bounded to one pass"
    }

    & $router -Event PostToolUse -Payload $editPayload -LogRoot $tmpLogs -Quiet | Out-Null
    $successfulVerifyPayload = [ordered]@{
        session_id = $sessionId
        cwd = $tmpRoot
        hook_event_name = "PostToolUse"
        tool_name = "Bash"
        tool_input = @{ command = "powershell -File .\verify.ps1" }
        tool_response = @{ exit_code = 0 }
    } | ConvertTo-Json -Depth 8 -Compress
    & $router -Event PostToolUse -Payload $successfulVerifyPayload -LogRoot $tmpLogs -Quiet | Out-Null
    $cleanStopRaw = ((& $router -Event Stop -Payload $stopPayload -LogRoot $tmpLogs -Quiet) -join "")
    if ($cleanStopRaw.Trim() -ne "{}") {
        throw "Stop continued even though a successful verification followed the edit"
    }
    Add-Check -Name "hook-verification-loop" -Status "passed" -Detail "failed checks do not close the loop; successful checks do; continuation is bounded"

    $subagentStopPayload = [ordered]@{
        session_id = $sessionId
        cwd = $tmpRoot
        hook_event_name = "SubagentStop"
        agent_id = "agent-test"
        agent_type = "tester"
        stop_hook_active = $false
    } | ConvertTo-Json -Depth 8 -Compress
    $subagentStopRaw = ((& $router -Event SubagentStop -Payload $subagentStopPayload -LogRoot $tmpLogs -Quiet) -join "")
    if ($subagentStopRaw.Trim() -ne "{}") {
        throw "SubagentStop must emit valid empty JSON when it has no continuation decision"
    }

    $persisted = (Get-ChildItem -LiteralPath $tmpLogs -File -Recurse | ForEach-Object {
        Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue
    }) -join "`n"
    foreach ($prohibited in @($secret, "raw message must not persist", "raw summary must not persist", "private patch body", "git reset --hard")) {
        if ($persisted -match [regex]::Escape($prohibited)) {
            throw "hook router persisted prohibited payload content"
        }
    }
    if ($persisted -notmatch 'payload_sha256|"sha256"') {
        throw "hook router did not preserve payload provenance hashes"
    }
    Add-Check -Name "hook-privacy" -Status "passed" -Detail "adversarial prompt, command, response, and summary content stayed out of hook artifacts"
} finally {
    if (Test-Path -LiteralPath $tmpRoot) {
        Remove-Item -LiteralPath $tmpRoot -Recurse -Force
    }
}

[ordered]@{
    schema = "codex-workflow-core-test-v2"
    status = "success"
    codex_home = $codexHomePath
    checks = $checks.ToArray()
} | ConvertTo-Json -Depth 8 -Compress
