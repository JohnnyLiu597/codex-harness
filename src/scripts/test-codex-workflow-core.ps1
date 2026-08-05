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

function Get-TestSha256Text {
    param([string]$Text)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-TestSessionKey {
    param([string]$SessionId)

    return (Get-TestSha256Text -Text $SessionId).Substring(0, 24)
}

function New-ToolHookPayload {
    param(
        [string]$SessionId,
        [string]$Cwd,
        [ValidateSet('PreToolUse', 'PostToolUse')]
        [string]$EventName,
        [string]$ToolName,
        [string]$ToolUseId,
        [string]$Command,
        [object]$ToolResponse = $null
    )

    $payload = [ordered]@{
        session_id = $SessionId
        turn_id = 'turn-' + $SessionId
        cwd = $Cwd
        hook_event_name = $EventName
        tool_name = $ToolName
        tool_use_id = $ToolUseId
        tool_input = @{ command = $Command }
    }
    if ($null -ne $ToolResponse) {
        $payload.tool_response = $ToolResponse
    }
    return $payload | ConvertTo-Json -Depth 10 -Compress
}

function ConvertFrom-HookJson {
    param([string]$Text, [string]$Label)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "$Label did not emit JSON."
    }
    try {
        return $Text | ConvertFrom-Json
    } catch {
        throw "$Label emitted invalid JSON: $($_.Exception.Message)"
    }
}

function Invoke-HookEntryProcess {
    param(
        [string]$EntryPath,
        [string]$EventName,
        [string]$Payload,
        [string]$CodexHomePath,
        [string]$UserProfilePath
    )

    $powerShellPath = (Get-Command powershell.exe -ErrorAction Stop).Source
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $powerShellPath
    $startInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $EntryPath + '" -Event ' + $EventName
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.EnvironmentVariables['CODEX_HOME'] = $CodexHomePath
    $startInfo.EnvironmentVariables['USERPROFILE'] = $UserProfilePath

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw 'Could not start isolated hook entry process.' }
    $process.StandardInput.Write($Payload)
    $process.StandardInput.Close()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    if (-not $process.WaitForExit(10000)) {
        try { $process.Kill() } catch { }
        throw 'Isolated hook entry process timed out.'
    }

    return [pscustomobject]@{
        exit_code = $process.ExitCode
        stdout = $stdout
        stderr = $stderr
    }
}

function Invoke-TestGit {
    param([string]$Root, [string[]]$Arguments)

    & git -C $Root @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed in $Root"
    }
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

$preToolMatchers = @($hooks.hooks.PreToolUse | ForEach-Object { [string]$_.matcher })
if (@($preToolMatchers | Where-Object { $_ -in @('.*', '^.*$') }).Count -eq 0) {
    throw 'PreToolUse must inspect every tool while the weekly restricted mode can be active.'
}
Add-Check -Name 'hook-all-tool-guard' -Status 'passed' -Detail 'PreToolUse covers shell, file, MCP, app, and connector tools'

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
    $sessionId = "workflow-core-self-test-" + [guid]::NewGuid().ToString("N")
    $secret = "sk-abcdefghijklmnopqrstuvwxyz1234567890"
    $gitRoot = Join-Path $tmpRoot 'git-workspace'
    $gitLogs = Join-Path $tmpRoot 'git-hook-logs'
    New-Item -ItemType Directory -Force -Path $gitRoot | Out-Null
    Invoke-TestGit -Root $gitRoot -Arguments @('init', '--quiet')
    Set-Content -LiteralPath (Join-Path $gitRoot 'tracked.txt') -Value 'baseline' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $gitRoot 'verify.ps1') -Value 'exit 0' -Encoding UTF8
    Invoke-TestGit -Root $gitRoot -Arguments @('add', 'tracked.txt', 'verify.ps1')
    Invoke-TestGit -Root $gitRoot -Arguments @('-c', 'user.name=Codex Hook Test', '-c', 'user.email=codex-hook@example.invalid', 'commit', '--quiet', '-m', 'baseline')

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

    $guardCodexHome = Join-Path $tmpRoot 'weekly-guard-home'
    $guardCwd = Join-Path $tmpRoot 'weekly-worktree'
    $guardChildCwd = Join-Path $guardCwd 'nested'
    $guardOutsideCwd = Join-Path $tmpRoot 'weekly-outside'
    New-Item -ItemType Directory -Force -Path (Join-Path $guardCodexHome 'harness-learning'), $guardCwd, $guardChildCwd, $guardOutsideCwd | Out-Null
    $guardRunId = 'weekly-guard-' + [guid]::NewGuid().ToString('N')
    [ordered]@{
        schema = 'codex-weekly-harness-active-run-v1'
        run_id = $guardRunId
        started_at = (Get-Date).ToString('o')
        caller_cwd = $guardCwd
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $guardCodexHome 'harness-learning\active-run.json') -Encoding UTF8

    $startCommand = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' +
        (Join-Path $guardCodexHome 'scripts\invoke-weekly-harness-learning.ps1') + '" -Mode Start'
    $startPayload = [ordered]@{
        session_id = $sessionId
        cwd = $guardCwd
        hook_event_name = 'PostToolUse'
        tool_name = 'Bash'
        tool_input = @{ command = $startCommand }
        tool_response = @{ exit_code = 0 }
    } | ConvertTo-Json -Depth 8 -Compress
    & $router -Event PostToolUse -Payload $startPayload -CodexHome $guardCodexHome -LogRoot $tmpLogs -Quiet | Out-Null
    $boundActiveRun = Get-Content -LiteralPath (Join-Path $guardCodexHome 'harness-learning\active-run.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not ($boundActiveRun.PSObject.Properties.Name -contains 'session_key') -or [string]::IsNullOrWhiteSpace([string]$boundActiveRun.session_key)) {
        throw 'Weekly restricted mode did not bind the active run to the starting session.'
    }

    $weeklyWritePayload = [ordered]@{
        session_id = $sessionId
        cwd = $guardCwd
        hook_event_name = 'PreToolUse'
        tool_name = 'Bash'
        tool_input = @{ command = 'Set-Content -LiteralPath .\src\AGENTS.md -Value blocked' }
    } | ConvertTo-Json -Depth 8 -Compress
    $weeklyWriteDecision = ((& $router -Event PreToolUse -Payload $weeklyWritePayload -CodexHome $guardCodexHome -LogRoot $tmpLogs -Quiet) -join '') | ConvertFrom-Json
    if ($weeklyWriteDecision.hookSpecificOutput.permissionDecision -ne 'deny') {
        throw 'Weekly restricted mode allowed arbitrary shell execution.'
    }

    foreach ($guardedCwd in @($guardChildCwd, $guardOutsideCwd)) {
        $escapedCwdPayload = [ordered]@{
            session_id = $sessionId
            cwd = $guardedCwd
            hook_event_name = 'PreToolUse'
            tool_name = 'Bash'
            tool_input = @{ command = 'Set-Content -LiteralPath .\escape.txt -Value blocked' }
        } | ConvertTo-Json -Depth 8 -Compress
        $escapedDecision = ((& $router -Event PreToolUse -Payload $escapedCwdPayload -CodexHome $guardCodexHome -LogRoot $tmpLogs -Quiet) -join '') | ConvertFrom-Json
        if ($escapedDecision.hookSpecificOutput.permissionDecision -ne 'deny') {
            throw "Weekly restricted mode was bypassed by changing cwd to $guardedCwd"
        }
    }

    $unrelatedPayload = [ordered]@{
        session_id = 'unrelated-' + [guid]::NewGuid().ToString('N')
        cwd = $guardCwd
        hook_event_name = 'PreToolUse'
        tool_name = 'mcp__threads__read_thread'
        tool_input = @{}
    } | ConvertTo-Json -Depth 8 -Compress
    $unrelatedDecision = ((& $router -Event PreToolUse -Payload $unrelatedPayload -CodexHome $guardCodexHome -LogRoot $tmpLogs -Quiet) -join '')
    if (-not [string]::IsNullOrWhiteSpace($unrelatedDecision)) {
        throw 'Weekly restricted mode leaked into an unrelated session.'
    }

    $readToolPayload = [ordered]@{
        session_id = $sessionId
        cwd = $guardOutsideCwd
        hook_event_name = 'PreToolUse'
        tool_name = 'mcp__threads__read_thread'
        tool_input = @{}
    } | ConvertTo-Json -Depth 8 -Compress
    $readToolDecision = ((& $router -Event PreToolUse -Payload $readToolPayload -CodexHome $guardCodexHome -LogRoot $tmpLogs -Quiet) -join '')
    if (-not [string]::IsNullOrWhiteSpace($readToolDecision)) {
        throw 'Weekly restricted mode rejected an explicitly read-only tool.'
    }

    foreach ($spoofedMutationTool in @(
        'mcp__records__get_and_modify',
        'mcp__records__get_or_upsert_record',
        'mcp__calendar__list_and_reschedule',
        'mcp__notes__view_and_append',
        'mcp__issues__read_and_resolve'
    )) {
        $spoofedPayload = [ordered]@{
            session_id = $sessionId
            cwd = $guardOutsideCwd
            hook_event_name = 'PreToolUse'
            tool_name = $spoofedMutationTool
            tool_input = @{}
        } | ConvertTo-Json -Depth 8 -Compress
        $spoofedDecision = ((& $router -Event PreToolUse -Payload $spoofedPayload -CodexHome $guardCodexHome -LogRoot $tmpLogs -Quiet) -join '') | ConvertFrom-Json
        if ($spoofedDecision.hookSpecificOutput.permissionDecision -ne 'deny') {
            throw "Weekly restricted mode allowed a read-like mutation tool: $spoofedMutationTool"
        }
    }

    $writeToolPayload = [ordered]@{
        session_id = $sessionId
        cwd = $guardOutsideCwd
        hook_event_name = 'PreToolUse'
        tool_name = 'mcp__spreadsheets__write_range'
        tool_input = @{}
    } | ConvertTo-Json -Depth 8 -Compress
    $writeToolDecision = ((& $router -Event PreToolUse -Payload $writeToolPayload -CodexHome $guardCodexHome -LogRoot $tmpLogs -Quiet) -join '') | ConvertFrom-Json
    if ($writeToolDecision.hookSpecificOutput.permissionDecision -ne 'deny') {
        throw 'Weekly restricted mode allowed an external write tool.'
    }

    $weeklyPatchPayload = [ordered]@{
        session_id = $sessionId
        cwd = $guardCwd
        hook_event_name = 'PreToolUse'
        tool_name = 'apply_patch'
        tool_input = @{ patch = "*** Begin Patch`n*** Update File: $guardCwd\AGENTS.md`n@@`n-old`n+new`n*** End Patch" }
    } | ConvertTo-Json -Depth 8 -Compress
    $weeklyPatchDecision = ((& $router -Event PreToolUse -Payload $weeklyPatchPayload -CodexHome $guardCodexHome -LogRoot $tmpLogs -Quiet) -join '') | ConvertFrom-Json
    if ($weeklyPatchDecision.hookSpecificOutput.permissionDecision -ne 'deny') {
        throw 'Weekly restricted mode allowed a maintainable-file patch.'
    }

    $unregisteredInputPath = Join-Path $env:TEMP ("codex-weekly-input-$guardRunId-unregistered.json")
    Set-Content -LiteralPath $unregisteredInputPath -Value '{}' -Encoding UTF8
    try {
        $unregisteredCompleteCommand = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' +
            (Join-Path $guardCodexHome 'scripts\invoke-weekly-harness-learning.ps1') +
            '" -Mode Complete -RunId "' + $guardRunId + '" -InputPath "' + $unregisteredInputPath + '"'
        $unregisteredCompletePayload = [ordered]@{
            session_id = $sessionId
            cwd = $guardOutsideCwd
            hook_event_name = 'PreToolUse'
            tool_name = 'Bash'
            tool_input = @{ command = $unregisteredCompleteCommand }
        } | ConvertTo-Json -Depth 8 -Compress
        $unregisteredCompleteDecision = ((& $router -Event PreToolUse -Payload $unregisteredCompletePayload -CodexHome $guardCodexHome -LogRoot $tmpLogs -Quiet) -join '') | ConvertFrom-Json
        if ($unregisteredCompleteDecision.hookSpecificOutput.permissionDecision -ne 'deny') {
            throw 'Weekly restricted mode allowed an unregistered existing TEMP input.'
        }
    } finally {
        if (Test-Path -LiteralPath $unregisteredInputPath -PathType Leaf) {
            Remove-Item -LiteralPath $unregisteredInputPath -Force
        }
    }

    $weeklyInputPath = Join-Path $env:TEMP ("codex-weekly-input-$guardRunId-test.json")
    $weeklyInputPatch = "*** Begin Patch`n*** Add File: $weeklyInputPath`n+{`"schema`":`"codex-weekly-harness-learning-input-v1`"}`n*** End Patch"
    $weeklyInputPayload = [ordered]@{
        session_id = $sessionId
        cwd = $guardCwd
        hook_event_name = 'PreToolUse'
        tool_name = 'apply_patch'
        tool_input = @{ patch = $weeklyInputPatch }
    } | ConvertTo-Json -Depth 8 -Compress
    $weeklyInputDecision = ((& $router -Event PreToolUse -Payload $weeklyInputPayload -CodexHome $guardCodexHome -LogRoot $tmpLogs -Quiet) -join '')
    if (-not [string]::IsNullOrWhiteSpace($weeklyInputDecision)) {
        throw 'Weekly restricted mode rejected its bounded TEMP input patch.'
    }

    $secondInputPath = Join-Path $env:TEMP ("codex-weekly-input-$guardRunId-second.json")
    $secondInputPatch = "*** Begin Patch`n*** Add File: $secondInputPath`n+{`"schema`":`"codex-weekly-harness-learning-input-v1`"}`n*** End Patch"
    $secondInputPayload = [ordered]@{
        session_id = $sessionId
        cwd = $guardOutsideCwd
        hook_event_name = 'PreToolUse'
        tool_name = 'apply_patch'
        tool_input = @{ patch = $secondInputPatch }
    } | ConvertTo-Json -Depth 8 -Compress
    $secondInputDecision = ((& $router -Event PreToolUse -Payload $secondInputPayload -CodexHome $guardCodexHome -LogRoot $tmpLogs -Quiet) -join '') | ConvertFrom-Json
    if ($secondInputDecision.hookSpecificOutput.permissionDecision -ne 'deny') {
        throw 'Weekly restricted mode allowed a second TEMP input target.'
    }
    Set-Content -LiteralPath $weeklyInputPath -Value '{}' -Encoding UTF8

    $completeCommand = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' +
        (Join-Path $guardCodexHome 'scripts\invoke-weekly-harness-learning.ps1') +
        '" -Mode Complete -RunId "' + $guardRunId + '" -InputPath "' + $weeklyInputPath + '"'
    $weeklyCompletePayload = [ordered]@{
        session_id = $sessionId
        cwd = $guardCwd
        hook_event_name = 'PreToolUse'
        tool_name = 'Bash'
        tool_input = @{ command = $completeCommand }
    } | ConvertTo-Json -Depth 8 -Compress
    $weeklyCompleteDecision = ((& $router -Event PreToolUse -Payload $weeklyCompletePayload -CodexHome $guardCodexHome -LogRoot $tmpLogs -Quiet) -join '')
    if (-not [string]::IsNullOrWhiteSpace($weeklyCompleteDecision)) {
        throw 'Weekly restricted mode rejected the exact completion command.'
    }
    Remove-Item -LiteralPath $weeklyInputPath -Force
    Add-Check -Name 'hook-weekly-restricted-mode' -Status 'passed' -Detail 'weekly runs stay session-bound across cwd changes, use a fail-closed read-tool allowlist, deny unregistered or multiple TEMP inputs, and accept only the exact completion command'

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

    $verificationCommand = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\verify.ps1"'

    $falsePositiveSession = 'false-positive-' + [guid]::NewGuid().ToString('N')
    Set-Content -LiteralPath (Join-Path $gitRoot 'tracked.txt') -Value 'false-positive edit' -Encoding UTF8
    $falsePositiveEdit = New-ToolHookPayload -SessionId $falsePositiveSession -Cwd $gitRoot -EventName PostToolUse `
        -ToolName apply_patch -ToolUseId 'edit-false-positive' -Command 'private patch body' -ToolResponse @{ isError = $false }
    & $router -Event PostToolUse -Payload $falsePositiveEdit -LogRoot $gitLogs -Quiet | Out-Null
    $falsePositiveIndex = 0
    foreach ($falsePositiveCommand in @(
        "Write-Output 'tests passed'",
        'Set-Content -LiteralPath .\test-results.txt -Value ok',
        'Get-Content -LiteralPath .\verify.ps1',
        'git status --short tests'
    )) {
        $falsePositiveIndex++
        $toolUseId = "false-positive-$falsePositiveIndex"
        $falsePre = New-ToolHookPayload -SessionId $falsePositiveSession -Cwd $gitRoot -EventName PreToolUse `
            -ToolName Bash -ToolUseId $toolUseId -Command $falsePositiveCommand
        $falsePost = New-ToolHookPayload -SessionId $falsePositiveSession -Cwd $gitRoot -EventName PostToolUse `
            -ToolName Bash -ToolUseId $toolUseId -Command $falsePositiveCommand -ToolResponse @{ exit_code = 0 }
        & $router -Event PreToolUse -Payload $falsePre -LogRoot $gitLogs -Quiet | Out-Null
        & $router -Event PostToolUse -Payload $falsePost -LogRoot $gitLogs -Quiet | Out-Null
    }
    $falsePositiveStopPayload = [ordered]@{
        session_id = $falsePositiveSession
        turn_id = 'turn-' + $falsePositiveSession
        cwd = $gitRoot
        hook_event_name = 'Stop'
        stop_hook_active = $false
        last_assistant_message = 'done'
    } | ConvertTo-Json -Depth 8 -Compress
    $falsePositiveStopRaw = ((& $router -Event Stop -Payload $falsePositiveStopPayload -LogRoot $gitLogs -Quiet) -join '')
    $falsePositiveStop = ConvertFrom-HookJson -Text $falsePositiveStopRaw -Label 'False-positive Stop'
    if ($falsePositiveStop.decision -ne 'block') {
        throw 'Verification-like words in non-verification commands falsely closed the hook verification loop.'
    }

    $causalSession = 'causal-' + [guid]::NewGuid().ToString('N')
    Set-Content -LiteralPath (Join-Path $gitRoot 'tracked.txt') -Value 'causal edit' -Encoding UTF8
    $causalEdit = New-ToolHookPayload -SessionId $causalSession -Cwd $gitRoot -EventName PostToolUse `
        -ToolName apply_patch -ToolUseId 'edit-causal' -Command 'private patch body' -ToolResponse @{ isError = $false }
    & $router -Event PostToolUse -Payload $causalEdit -LogRoot $gitLogs -Quiet | Out-Null
    $unpairedVerifyPost = New-ToolHookPayload -SessionId $causalSession -Cwd $gitRoot -EventName PostToolUse `
        -ToolName Bash -ToolUseId 'verify-without-pre' -Command $verificationCommand -ToolResponse @{ exit_code = 0 }
    & $router -Event PostToolUse -Payload $unpairedVerifyPost -LogRoot $gitLogs -Quiet | Out-Null
    $causalStopPayload = [ordered]@{
        session_id = $causalSession
        turn_id = 'turn-' + $causalSession
        cwd = $gitRoot
        hook_event_name = 'Stop'
        stop_hook_active = $false
    } | ConvertTo-Json -Depth 8 -Compress
    $causalStop = ConvertFrom-HookJson `
        -Text ((& $router -Event Stop -Payload $causalStopPayload -LogRoot $gitLogs -Quiet) -join '') `
        -Label 'Causal Stop'
    if ($causalStop.decision -ne 'block') {
        throw 'A PostToolUse verification without a matching PreToolUse tool_use_id falsely closed the loop.'
    }

    $overlapSession = 'overlap-' + [guid]::NewGuid().ToString('N')
    Set-Content -LiteralPath (Join-Path $gitRoot 'tracked.txt') -Value 'overlap edit one' -Encoding UTF8
    $overlapEditOne = New-ToolHookPayload -SessionId $overlapSession -Cwd $gitRoot -EventName PostToolUse `
        -ToolName apply_patch -ToolUseId 'edit-overlap-one' -Command 'private patch body one' -ToolResponse @{ isError = $false }
    & $router -Event PostToolUse -Payload $overlapEditOne -LogRoot $gitLogs -Quiet | Out-Null
    $overlapVerifyPre = New-ToolHookPayload -SessionId $overlapSession -Cwd $gitRoot -EventName PreToolUse `
        -ToolName Bash -ToolUseId 'verify-overlap' -Command $verificationCommand
    & $router -Event PreToolUse -Payload $overlapVerifyPre -LogRoot $gitLogs -Quiet | Out-Null
    Set-Content -LiteralPath (Join-Path $gitRoot 'tracked.txt') -Value 'overlap edit two' -Encoding UTF8
    $overlapEditTwo = New-ToolHookPayload -SessionId $overlapSession -Cwd $gitRoot -EventName PostToolUse `
        -ToolName apply_patch -ToolUseId 'edit-overlap-two' -Command 'private patch body two' -ToolResponse @{ isError = $false }
    & $router -Event PostToolUse -Payload $overlapEditTwo -LogRoot $gitLogs -Quiet | Out-Null
    $overlapVerifyPost = New-ToolHookPayload -SessionId $overlapSession -Cwd $gitRoot -EventName PostToolUse `
        -ToolName Bash -ToolUseId 'verify-overlap' -Command $verificationCommand -ToolResponse @{ exit_code = 0 }
    & $router -Event PostToolUse -Payload $overlapVerifyPost -LogRoot $gitLogs -Quiet | Out-Null
    $overlapStopPayload = [ordered]@{
        session_id = $overlapSession
        turn_id = 'turn-' + $overlapSession
        cwd = $gitRoot
        hook_event_name = 'Stop'
        stop_hook_active = $false
    } | ConvertTo-Json -Depth 8 -Compress
    $overlapStop = ConvertFrom-HookJson `
        -Text ((& $router -Event Stop -Payload $overlapStopPayload -LogRoot $gitLogs -Quiet) -join '') `
        -Label 'Overlap Stop'
    if ($overlapStop.decision -ne 'block') {
        throw 'An edit that overlapped a verification command did not make the check stale.'
    }

    $fingerprintSession = 'fingerprint-' + [guid]::NewGuid().ToString('N')
    Set-Content -LiteralPath (Join-Path $gitRoot 'tracked.txt') -Value 'verified edit' -Encoding UTF8
    $fingerprintEdit = New-ToolHookPayload -SessionId $fingerprintSession -Cwd $gitRoot -EventName PostToolUse `
        -ToolName apply_patch -ToolUseId 'edit-fingerprint' -Command 'private patch body' -ToolResponse @{ isError = $false }
    & $router -Event PostToolUse -Payload $fingerprintEdit -LogRoot $gitLogs -Quiet | Out-Null
    $fingerprintVerifyPre = New-ToolHookPayload -SessionId $fingerprintSession -Cwd $gitRoot -EventName PreToolUse `
        -ToolName Bash -ToolUseId 'verify-fingerprint' -Command $verificationCommand
    $fingerprintVerifyPost = New-ToolHookPayload -SessionId $fingerprintSession -Cwd $gitRoot -EventName PostToolUse `
        -ToolName Bash -ToolUseId 'verify-fingerprint' -Command $verificationCommand -ToolResponse @{ exit_code = 0 }
    & $router -Event PreToolUse -Payload $fingerprintVerifyPre -LogRoot $gitLogs -Quiet | Out-Null
    & $router -Event PostToolUse -Payload $fingerprintVerifyPost -LogRoot $gitLogs -Quiet | Out-Null
    $fingerprintStopPayload = [ordered]@{
        session_id = $fingerprintSession
        turn_id = 'turn-' + $fingerprintSession
        cwd = $gitRoot
        hook_event_name = 'Stop'
        stop_hook_active = $false
    } | ConvertTo-Json -Depth 8 -Compress
    $verifiedStopRaw = ((& $router -Event Stop -Payload $fingerprintStopPayload -LogRoot $gitLogs -Quiet) -join '')
    $verifiedStop = ConvertFrom-HookJson -Text $verifiedStopRaw -Label 'Verified Stop'
    if (@($verifiedStop.PSObject.Properties).Count -ne 0) {
        $verifiedStatePath = Join-Path $gitLogs ('state\' + (Get-TestSessionKey -SessionId $fingerprintSession) + '.json')
        $verifiedState = Get-Content -LiteralPath $verifiedStatePath -Raw -ErrorAction SilentlyContinue
        $preTrace = (Get-Content -LiteralPath (Join-Path $gitLogs ('hook-pretooluse-' + (Get-Date -Format 'yyyyMMdd') + '.jsonl')) -Tail 1 -ErrorAction SilentlyContinue) -join ''
        $postTrace = (Get-Content -LiteralPath (Join-Path $gitLogs ('hook-posttooluse-' + (Get-Date -Format 'yyyyMMdd') + '.jsonl')) -Tail 1 -ErrorAction SilentlyContinue) -join ''
        throw "Stop continued even though a causally paired verification covered the current workspace fingerprint. Output=$verifiedStopRaw State=$verifiedState Pre=$preTrace Post=$postTrace"
    }

    Set-Content -LiteralPath (Join-Path $gitRoot 'tracked.txt') -Value 'unobserved write after verification' -Encoding UTF8
    $staleStopRaw = ((& $router -Event Stop -Payload $fingerprintStopPayload -LogRoot $gitLogs -Quiet) -join '')
    $staleStop = ConvertFrom-HookJson -Text $staleStopRaw -Label 'Stale fingerprint Stop'
    if ($staleStop.decision -ne 'block') {
        throw 'Stop did not detect a workspace write that occurred after the last verified fingerprint.'
    }
    $continuedStopPayload = [ordered]@{
        session_id = $fingerprintSession
        turn_id = 'turn-' + $fingerprintSession
        cwd = $gitRoot
        hook_event_name = 'Stop'
        stop_hook_active = $true
        last_assistant_message = 'verification blocker reported'
    } | ConvertTo-Json -Depth 8 -Compress
    $continuedStopRaw = ((& $router -Event Stop -Payload $continuedStopPayload -LogRoot $gitLogs -Quiet) -join '')
    $continuedStop = ConvertFrom-HookJson -Text $continuedStopRaw -Label 'Continued Stop'
    if (@($continuedStop.PSObject.Properties).Count -ne 0) {
        throw 'Stop continuation was not bounded to one valid empty JSON response.'
    }
    Add-Check -Name 'hook-verification-loop-v3' -Status 'passed' -Detail 'verification requires a real command, matching tool_use_id, stable bounded Git fingerprint, and a current Stop fingerprint; continuation JSON remains bounded'

    $lockSession = 'lock-degradation-' + [guid]::NewGuid().ToString('N')
    $lockLogs = Join-Path $tmpRoot 'lock-hook-logs'
    $lockEditOne = New-ToolHookPayload -SessionId $lockSession -Cwd $tmpRoot -EventName PostToolUse `
        -ToolName apply_patch -ToolUseId 'lock-edit-one' -Command 'first edit' -ToolResponse @{ isError = $false }
    & $router -Event PostToolUse -Payload $lockEditOne -LogRoot $lockLogs -Quiet | Out-Null
    $lockStatePath = Join-Path $lockLogs ('state\' + (Get-TestSessionKey -SessionId $lockSession) + '.json')
    if (-not (Test-Path -LiteralPath $lockStatePath -PathType Leaf)) {
        throw 'Lock degradation setup did not create the initial state file.'
    }
    $lockStateBefore = (Get-FileHash -LiteralPath $lockStatePath -Algorithm SHA256).Hash
    $mutexName = 'codex-hook-state-' + (Get-TestSessionKey -SessionId $lockSession)
    $mutexMarker = Join-Path $tmpRoot 'state-mutex-held.txt'
    $mutexJob = Start-Job -ScriptBlock {
        param($Name, $Marker)
        $mutex = New-Object System.Threading.Mutex($false, $Name)
        $taken = $false
        try {
            $taken = $mutex.WaitOne(5000)
            if ($taken) {
                Set-Content -LiteralPath $Marker -Value 'held' -Encoding ASCII
                Start-Sleep -Seconds 6
            }
        } finally {
            if ($taken) { try { $mutex.ReleaseMutex() } catch { } }
            $mutex.Dispose()
        }
    } -ArgumentList $mutexName, $mutexMarker
    try {
        $waitDeadline = [DateTime]::UtcNow.AddSeconds(5)
        while (-not (Test-Path -LiteralPath $mutexMarker -PathType Leaf) -and [DateTime]::UtcNow -lt $waitDeadline) {
            Start-Sleep -Milliseconds 50
        }
        if (-not (Test-Path -LiteralPath $mutexMarker -PathType Leaf)) {
            throw 'Could not acquire the state mutex in the lock degradation test.'
        }
        $lockEditTwo = New-ToolHookPayload -SessionId $lockSession -Cwd $tmpRoot -EventName PostToolUse `
            -ToolName apply_patch -ToolUseId 'lock-edit-two' -Command 'second edit' -ToolResponse @{ isError = $false }
        & $router -Event PostToolUse -Payload $lockEditTwo -LogRoot $lockLogs -Quiet | Out-Null
        $lockStateAfter = (Get-FileHash -LiteralPath $lockStatePath -Algorithm SHA256).Hash
        if ($lockStateAfter -ne $lockStateBefore) {
            throw 'The hook router wrote shared state after failing to acquire the session mutex.'
        }
    } finally {
        Stop-Job -Job $mutexJob -ErrorAction SilentlyContinue | Out-Null
        Receive-Job -Job $mutexJob -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Job $mutexJob -Force -ErrorAction SilentlyContinue
    }
    Add-Check -Name 'hook-lock-degradation' -Status 'passed' -Detail 'state mutex failure leaves shared session state unchanged'

    $entrySource = Join-Path $codexHomePath 'scripts\codex-hook.ps1'
    $customHome = Join-Path $tmpRoot 'custom-codex-home'
    $customScripts = Join-Path $customHome 'scripts'
    $fallbackProfile = Join-Path $tmpRoot 'fallback-user-profile'
    New-Item -ItemType Directory -Force -Path $customScripts, $fallbackProfile | Out-Null
    Copy-Item -LiteralPath $entrySource, $router -Destination $customScripts -Force
    $customSession = 'custom-home-' + [guid]::NewGuid().ToString('N')
    $customPayload = New-ToolHookPayload -SessionId $customSession -Cwd $tmpRoot -EventName PostToolUse `
        -ToolName Bash -ToolUseId 'custom-home-observe' -Command 'Write-Output ok' -ToolResponse @{ exit_code = 0 }
    $customResult = Invoke-HookEntryProcess `
        -EntryPath (Join-Path $customScripts 'codex-hook.ps1') `
        -EventName PostToolUse `
        -Payload $customPayload `
        -CodexHomePath $customHome `
        -UserProfilePath $fallbackProfile
    if ($customResult.exit_code -ne 0) {
        throw "Custom CODEX_HOME hook entry failed: $($customResult.stderr)"
    }
    $customStatePath = Join-Path $customHome ('hook-logs\state\' + (Get-TestSessionKey -SessionId $customSession) + '.json')
    $fallbackStatePath = Join-Path $fallbackProfile ('.codex\hook-logs\state\' + (Get-TestSessionKey -SessionId $customSession) + '.json')
    if (-not (Test-Path -LiteralPath $customStatePath -PathType Leaf) -or (Test-Path -LiteralPath $fallbackStatePath -PathType Leaf)) {
        throw 'codex-hook.ps1 did not propagate CODEX_HOME to the router.'
    }

    $failureHome = Join-Path $tmpRoot 'router-failure-home'
    $failureScripts = Join-Path $failureHome 'scripts'
    $failureProfile = Join-Path $tmpRoot 'router-failure-profile'
    New-Item -ItemType Directory -Force -Path $failureScripts, (Join-Path $failureHome 'harness-learning'), $failureProfile | Out-Null
    Copy-Item -LiteralPath $entrySource -Destination $failureScripts -Force
    Set-Content -LiteralPath (Join-Path $failureScripts 'codex-hook-router.ps1') -Value "throw 'simulated router failure'" -Encoding UTF8
    $failureSession = 'router-failure-' + [guid]::NewGuid().ToString('N')
    [ordered]@{
        schema = 'codex-weekly-harness-active-run-v1'
        run_id = 'router-failure-run'
        started_at = (Get-Date).ToString('o')
        caller_cwd = $tmpRoot
        session_key = Get-TestSessionKey -SessionId $failureSession
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $failureHome 'harness-learning\active-run.json') -Encoding UTF8
    $restrictedFailurePayload = New-ToolHookPayload -SessionId $failureSession -Cwd $tmpRoot -EventName PreToolUse `
        -ToolName mcp__spreadsheets__write_range -ToolUseId 'restricted-router-failure' -Command ''
    $restrictedFailureResult = Invoke-HookEntryProcess `
        -EntryPath (Join-Path $failureScripts 'codex-hook.ps1') `
        -EventName PreToolUse `
        -Payload $restrictedFailurePayload `
        -CodexHomePath $failureHome `
        -UserProfilePath $failureProfile
    if ($restrictedFailureResult.exit_code -ne 0) {
        throw 'Weekly restricted router failure did not degrade to an official deny response.'
    }
    $restrictedFailureDecision = ConvertFrom-HookJson -Text $restrictedFailureResult.stdout -Label 'Weekly router failure'
    if ($restrictedFailureDecision.hookSpecificOutput.permissionDecision -ne 'deny') {
        throw 'Weekly restricted mode silently lost protection when the router failed.'
    }

    $ordinaryFailureSession = 'ordinary-router-failure-' + [guid]::NewGuid().ToString('N')
    $ordinaryFailurePayload = New-ToolHookPayload -SessionId $ordinaryFailureSession -Cwd $tmpRoot -EventName PreToolUse `
        -ToolName Bash -ToolUseId 'ordinary-router-failure' -Command 'Write-Output ok'
    $ordinaryFailureResult = Invoke-HookEntryProcess `
        -EntryPath (Join-Path $failureScripts 'codex-hook.ps1') `
        -EventName PreToolUse `
        -Payload $ordinaryFailurePayload `
        -CodexHomePath $failureHome `
        -UserProfilePath $failureProfile
    if ($ordinaryFailureResult.exit_code -ne 0 -or -not [string]::IsNullOrWhiteSpace($ordinaryFailureResult.stdout)) {
        throw 'An ordinary observational router failure did not fail open.'
    }
    Add-Check -Name 'hook-entry-reliability' -Status 'passed' -Detail 'custom CODEX_HOME is propagated, ordinary router failures fail open, and weekly restricted router failures fail closed'

    foreach ($eventProperty in $hooks.hooks.PSObject.Properties) {
        foreach ($group in @($eventProperty.Value)) {
            foreach ($hook in @($group.hooks)) {
                if ([string]$hook.command -notmatch 'CODEX_HOME' -or [string]$hook.commandWindows -notmatch 'CODEX_HOME') {
                    throw "Hook wiring for $($eventProperty.Name) does not honor CODEX_HOME on both command paths."
                }
            }
        }
    }
    Add-Check -Name 'hook-codex-home-wiring' -Status 'passed' -Detail 'all hook commands resolve their entry point from CODEX_HOME with a default-home fallback'

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
