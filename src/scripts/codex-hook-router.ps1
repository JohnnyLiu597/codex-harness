param(
    [ValidateSet("SessionStart", "SessionEnd", "PreToolUse", "PermissionRequest", "PostToolUse", "PreCompact", "PostCompact", "UserPromptSubmit", "SubagentStart", "SubagentStop", "Stop")]
    [string]$Event = "Stop",
    [string]$Payload = "",
    [string]$CodexHome = "$env:USERPROFILE\.codex",
    [string]$LogRoot = "",
    [switch]$Quiet,
    [switch]$PassThru
)

$ErrorActionPreference = "SilentlyContinue"

function Get-Sha256Text {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return "" }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash)).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-JsonPayloadFacts {
    param([string]$Text)

    $facts = [ordered]@{
        keys = @()
        payload_length = if ($null -eq $Text) { 0 } else { $Text.Length }
        payload_sha256 = Get-Sha256Text -Text $Text
        parse_status = if ([string]::IsNullOrWhiteSpace($Text)) { "empty" } else { "raw" }
        json = $null
    }

    if ([string]::IsNullOrWhiteSpace($Text)) { return $facts }

    try {
        $json = $Text | ConvertFrom-Json
        $facts.parse_status = "json"
        $facts.keys = @($json.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object -Unique)
        $facts.json = $json
    } catch {
        $facts.parse_status = "invalid-json"
    }

    return $facts
}

function Get-WorkingRoot {
    param([object]$Json)

    if ($null -ne $Json -and $Json.cwd -and (Test-Path -LiteralPath ([string]$Json.cwd) -PathType Container)) {
        try { return (Resolve-Path -LiteralPath ([string]$Json.cwd)).Path } catch { }
    }
    return (Get-Location).Path
}

function Get-GitFacts {
    param([string]$Root)

    $facts = [ordered]@{
        is_git_repo = $false
        dirty = $null
        changed_count = 0
        branch = ""
        head = ""
    }

    try {
        $inside = git -C $Root rev-parse --is-inside-work-tree 2>$null
        if ($inside -ne "true") { return $facts }
        $facts.is_git_repo = $true
        $facts.branch = [string](git -C $Root branch --show-current 2>$null)
        $facts.head = [string](git -C $Root rev-parse --short HEAD 2>$null)
        $changes = @(git -C $Root status --porcelain=v1 2>$null)
        $facts.changed_count = $changes.Count
        $facts.dirty = $changes.Count -gt 0
    } catch { }

    return $facts
}

function Get-ProjectFacts {
    param([string]$Root)

    $anchors = @("AGENTS.md", "mission.md", "CONTEXT.md", "MEMORY.md", "README.md", "docs\testing.md", "docs\smoke.md")
    $present = @()
    foreach ($relative in $anchors) {
        if (Test-Path -LiteralPath (Join-Path $Root $relative)) { $present += $relative }
    }

    $currentSummary = Join-Path $Root "artifacts\session-summaries\current.md"
    return [ordered]@{
        harness_files_present = $present
        has_project_harness = $present.Count -gt 0
        current_session_summary = if (Test-Path -LiteralPath $currentSummary) { $currentSummary } else { "" }
    }
}

function Get-CodexHarnessDriftFacts {
    param([string]$Root, [string]$CodexHomePath)

    $sourceRoot = $env:CODEX_HARNESS_SOURCE
    $isCodexHarness = $false
    if (-not [string]::IsNullOrWhiteSpace($sourceRoot)) {
        try { $sourceRoot = (Resolve-Path -LiteralPath $sourceRoot).Path } catch { $sourceRoot = "" }
    }
    try {
        $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
        $isCodexHarness = (-not [string]::IsNullOrWhiteSpace($sourceRoot)) -and
            $resolvedRoot.StartsWith($sourceRoot, [System.StringComparison]::OrdinalIgnoreCase)
    } catch { }

    $runtimeSkill = Join-Path $CodexHomePath "skills\project-harness-optimizer\SKILL.md"
    $sourceSkill = if ($sourceRoot) { Join-Path $sourceRoot "src\skills\project-harness-optimizer\SKILL.md" } else { "" }
    $skillDrift = $null
    if ((Test-Path -LiteralPath $runtimeSkill) -and $sourceSkill -and (Test-Path -LiteralPath $sourceSkill)) {
        try {
            $skillDrift = (Get-FileHash -LiteralPath $runtimeSkill -Algorithm SHA256).Hash -ne
                (Get-FileHash -LiteralPath $sourceSkill -Algorithm SHA256).Hash
        } catch { }
    }

    return [ordered]@{
        source_root = $sourceRoot
        current_repo_is_codex_harness = $isCodexHarness
        project_harness_optimizer_drift = $skillDrift
    }
}

function Get-ToolName {
    param([object]$Json)
    if ($null -eq $Json -or -not $Json.tool_name) { return "" }
    return [string]$Json.tool_name
}

function Get-ToolCommand {
    param([object]$Json)
    if ($null -eq $Json -or $null -eq $Json.tool_input) { return "" }
    foreach ($name in @("command", "cmd")) {
        if ($Json.tool_input.PSObject.Properties.Name -contains $name) {
            return [string]$Json.tool_input.$name
        }
    }
    return ""
}

function Get-ToolExitCode {
    param([object]$Json)

    if ($null -eq $Json -or $null -eq $Json.tool_response) { return $null }
    $response = $Json.tool_response
    foreach ($name in @("exit_code", "exitCode")) {
        if ($response.PSObject.Properties.Name -contains $name) {
            try { return [int]$response.$name } catch { }
        }
    }

    $text = if ($response -is [string]) { [string]$response } else { $response | ConvertTo-Json -Depth 12 -Compress }
    foreach ($pattern in @('"exit_code"\s*:\s*(-?\d+)', '(?i)process exited with code\s+(-?\d+)')) {
        $match = [regex]::Match($text, $pattern)
        if ($match.Success) {
            try { return [int]$match.Groups[1].Value } catch { }
        }
    }
    return $null
}

function Test-ToolSucceeded {
    param([object]$Json)

    if ($null -eq $Json -or $null -eq $Json.tool_response) { return $true }
    $response = $Json.tool_response
    foreach ($name in @("isError", "is_error")) {
        if ($response.PSObject.Properties.Name -contains $name -and [bool]$response.$name) { return $false }
    }
    $exitCode = Get-ToolExitCode -Json $Json
    if ($null -ne $exitCode) { return $exitCode -eq 0 }
    return $true
}

function Get-SessionKey {
    param([object]$Json, [string]$Root)

    $source = $Root
    if ($null -ne $Json -and $Json.session_id) { $source = [string]$Json.session_id }
    $hash = Get-Sha256Text -Text $source
    if ($hash.Length -lt 24) { return $hash }
    return $hash.Substring(0, 24)
}

function Read-HookState {
    param([string]$Path, [string]$SessionKey)

    $state = $null
    if (Test-Path -LiteralPath $Path) {
        try { $state = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { }
    }
    if ($null -eq $state) {
        $state = [pscustomobject]@{
            schema = "codex-hook-state-v2"
            session_key = $SessionKey
            edit_sequence = 0
            verified_edit_sequence = 0
            acknowledged_edit_sequence = 0
            stop_continuations = 0
            last_edit_at = ""
            last_verification_at = ""
            last_event = ""
            updated_at = ""
        }
    }

    $defaults = [ordered]@{
        schema = "codex-hook-state-v2"
        session_key = $SessionKey
        edit_sequence = 0
        verified_edit_sequence = 0
        acknowledged_edit_sequence = 0
        stop_continuations = 0
        last_edit_at = ""
        last_verification_at = ""
        last_event = ""
        updated_at = ""
    }
    foreach ($name in $defaults.Keys) {
        if ($state.PSObject.Properties.Name -notcontains $name) {
            $state | Add-Member -NotePropertyName $name -NotePropertyValue $defaults[$name]
        }
    }
    $state.schema = "codex-hook-state-v2"
    return $state
}

function Write-HookState {
    param([string]$Path, [object]$State)

    $State.updated_at = (Get-Date).ToUniversalTime().ToString("o")
    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $temporary = Join-Path $directory ((Split-Path -Leaf $Path) + "." + [guid]::NewGuid().ToString("N") + ".tmp")
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Test-VerificationCommand {
    param([string]$Command)

    if ([string]::IsNullOrWhiteSpace($Command)) { return $false }
    return $Command -match '(?i)(^|[\s\\/.-])(test|tests|verify|verification|check|lint|build|typecheck|pytest|jest|playwright|tsc|cargo\s+test|go\s+test|dotnet\s+test|mvn\s+test|gradle\w*\s+test|git\s+diff\s+--check)([\s\\/.-]|$)'
}

function Test-WriteTool {
    param([string]$ToolName, [string]$Command)

    if ($ToolName -eq "apply_patch") { return $true }
    if ($ToolName -ne "Bash" -or [string]::IsNullOrWhiteSpace($Command)) { return $false }
    return $Command -match '(?i)(Set-Content|Add-Content|Out-File|Copy-Item|Move-Item|New-Item\s+[^\r\n]*-ItemType\s+(File|Directory)|npm\s+(install|add)|pnpm\s+(install|add)|yarn\s+add|git\s+(merge|rebase|cherry-pick))'
}

function Get-DenyReason {
    param([string]$Command, [string]$Root)

    if ([string]::IsNullOrWhiteSpace($Command)) { return "" }
    $dangerous = @(
        '(?i)git\s+reset\s+--hard',
        '(?i)git\s+clean\s+-[^\r\n]*f',
        '(?i)git\s+push\s+[^\r\n]*--force',
        '(?i)(rm|rmdir)\s+[^\r\n]*(-rf|-fr|/s)',
        '(?i)Remove-Item\s+[^\r\n]*-Recurse[^\r\n]*-Force',
        '(?i)Remove-Item\s+[^\r\n]*-Force[^\r\n]*-Recurse'
    )
    foreach ($pattern in $dangerous) {
        if ($Command -match $pattern) {
            return "Destructive or forceful command blocked by the global Codex harness. Use a reversible operation or an explicitly reviewed manual path."
        }
    }

    $isHarnessRepo = $false
    try {
        $repoRoot = [string](git -C $Root rev-parse --show-toplevel 2>$null)
        $isHarnessRepo = (Split-Path -Leaf $repoRoot.Trim()) -eq "codex-harness"
    } catch { }
    $forbiddenRuntimeState = '(?i)(config\.toml|auth\.json|\.sqlite(?:-shm|-wal)?|[\\/](logs?|sessions?|plugins?|cache|browser(?:[ ._-]?state)?)[\\/])'
    if ($isHarnessRepo -and $Command -match '(?i)\.codex' -and $Command -match $forbiddenRuntimeState) {
        return "Runtime-only state must not be copied into the publishable harness source."
    }

    return ""
}

function Test-HighConfidenceSecret {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    foreach ($pattern in @(
        '(?i)\bsk-[A-Za-z0-9_-]{20,}\b',
        '\bgh[pousr]_[A-Za-z0-9]{20,}\b',
        '\bAKIA[0-9A-Z]{16}\b',
        '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
    )) {
        if ($Text -match $pattern) { return $true }
    }
    return $false
}

function New-AdditionalContextOutput {
    param([string]$EventName, [string]$Context)

    return [ordered]@{
        hookSpecificOutput = [ordered]@{
            hookEventName = $EventName
            additionalContext = $Context
        }
    }
}

$codexHomePath = if (Test-Path -LiteralPath $CodexHome) { (Resolve-Path -LiteralPath $CodexHome).Path } else { $CodexHome }
if (-not $LogRoot) { $LogRoot = Join-Path $codexHomePath "hook-logs" }
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

$timestamp = (Get-Date).ToUniversalTime().ToString("o")
$date = Get-Date -Format "yyyyMMdd"
$payloadFacts = Get-JsonPayloadFacts -Text $Payload
$payloadJson = $payloadFacts.json
$cwd = Get-WorkingRoot -Json $payloadJson
$gitFacts = Get-GitFacts -Root $cwd
$projectFacts = Get-ProjectFacts -Root $cwd
$driftFacts = Get-CodexHarnessDriftFacts -Root $cwd -CodexHomePath $codexHomePath
$toolName = Get-ToolName -Json $payloadJson
$toolCommand = Get-ToolCommand -Json $payloadJson
$sessionKey = Get-SessionKey -Json $payloadJson -Root $cwd
$statePath = Join-Path $LogRoot ("state\" + $sessionKey + ".json")
$eventOutput = if ($Event -in @("SubagentStop", "Stop")) { [ordered]@{} } else { $null }
$decision = "observe"
$recommendations = New-Object System.Collections.Generic.List[string]

if ($Event -in @("PreToolUse", "PermissionRequest") -and $toolName -eq "Bash") {
    $denyReason = Get-DenyReason -Command $toolCommand -Root $cwd
    if ($denyReason) {
        $decision = "deny"
        if ($Event -eq "PreToolUse") {
            $eventOutput = [ordered]@{
                systemMessage = $denyReason
                hookSpecificOutput = [ordered]@{
                    hookEventName = "PreToolUse"
                    permissionDecision = "deny"
                    permissionDecisionReason = $denyReason
                }
            }
        } else {
            $eventOutput = [ordered]@{
                systemMessage = $denyReason
                hookSpecificOutput = [ordered]@{
                    hookEventName = "PermissionRequest"
                    decision = [ordered]@{ behavior = "deny"; message = $denyReason }
                }
            }
        }
    }
}

if ($Event -eq "UserPromptSubmit" -and $null -ne $payloadJson -and (Test-HighConfidenceSecret -Text ([string]$payloadJson.prompt))) {
    $decision = "deny-secret-like-prompt"
    $eventOutput = [ordered]@{
        decision = "block"
        reason = "A credential-like value was detected in the prompt. Remove or redact it before continuing."
    }
}

$mutex = $null
$lockTaken = $false
$state = $null
try {
    $mutex = New-Object System.Threading.Mutex($false, ("codex-hook-state-" + $sessionKey))
    try { $lockTaken = $mutex.WaitOne(2000) } catch { $lockTaken = $false }
    $state = Read-HookState -Path $statePath -SessionKey $sessionKey

    if ($Event -eq "PostToolUse" -and (Test-ToolSucceeded -Json $payloadJson)) {
        if (Test-WriteTool -ToolName $toolName -Command $toolCommand) {
            $state.edit_sequence = [int]$state.edit_sequence + 1
            $state.stop_continuations = 0
            $state.last_edit_at = $timestamp
            $decision = "edit-observed"
        }
        if ($toolName -eq "Bash" -and (Test-VerificationCommand -Command $toolCommand)) {
            $state.verified_edit_sequence = [int]$state.edit_sequence
            $state.stop_continuations = 0
            $state.last_verification_at = $timestamp
            $decision = "verification-observed"
        }
    }

    if ($Event -eq "SessionStart" -and $projectFacts.current_session_summary) {
        $eventOutput = New-AdditionalContextOutput -EventName $Event -Context "A durable session summary exists at $($projectFacts.current_session_summary). Read it only when resuming related work."
    }

    if ($Event -eq "PreCompact") {
        $recommendations.Add("Preserve the objective, decisions, verification evidence, and next action before compaction when the task spans context windows.") | Out-Null
    }

    if ($Event -eq "SubagentStart") {
        $eventOutput = New-AdditionalContextOutput -EventName $Event -Context "Keep the delegated scope bounded. Return ownership, changed files, checks, risks, and unresolved work; do not return raw logs."
    }

    if ($Event -eq "Stop") {
        $pendingFloor = [math]::Max([int]$state.verified_edit_sequence, [int]$state.acknowledged_edit_sequence)
        $pendingVerification = [int]$state.edit_sequence -gt $pendingFloor
        $stopHookActive = $false
        if ($null -ne $payloadJson -and $payloadJson.stop_hook_active) { $stopHookActive = [bool]$payloadJson.stop_hook_active }

        if ($pendingVerification -and -not $stopHookActive -and [int]$state.stop_continuations -lt 1) {
            $state.stop_continuations = [int]$state.stop_continuations + 1
            $decision = "continue-for-verification"
            $eventOutput = [ordered]@{
                decision = "block"
                reason = "Tracked edits have no observed successful verification command. Run the smallest meaningful check, then report the evidence or a precise blocker."
            }
        } elseif ($pendingVerification) {
            $state.acknowledged_edit_sequence = [int]$state.edit_sequence
            $decision = "unverified-acknowledged"
            $eventOutput = [ordered]@{}
        }
    }

    $state.last_event = $Event
    Write-HookState -Path $statePath -State $state
} finally {
    if ($lockTaken -and $null -ne $mutex) {
        try { $mutex.ReleaseMutex() } catch { }
    }
    if ($null -ne $mutex) { $mutex.Dispose() }
}

if ($gitFacts.is_git_repo -and $gitFacts.dirty) {
    $recommendations.Add("Keep verification evidence proportional to the changed surface.") | Out-Null
}
if ($driftFacts.current_repo_is_codex_harness -and $driftFacts.project_harness_optimizer_drift) {
    $recommendations.Add("The installed optimizer differs from source; finish the selected maintenance lane before publishing.") | Out-Null
}

$pendingFloor = [math]::Max([int]$state.verified_edit_sequence, [int]$state.acknowledged_edit_sequence)
$pendingVerification = [int]$state.edit_sequence -gt $pendingFloor
$logPath = Join-Path $LogRoot ("hook-" + $Event.ToLowerInvariant() + "-" + $date + ".jsonl")
$latestPath = if ($Event -eq "Stop") { Join-Path $LogRoot "latest-stop.txt" } else { Join-Path $LogRoot "latest-hook.txt" }
$entry = [ordered]@{
    schema = "codex-hook-event-v2"
    ts = $timestamp
    event = $Event
    cwd = $cwd
    decision = $decision
    tool_name = $toolName
    git = $gitFacts
    project = $projectFacts
    codex_harness = $driftFacts
    payload = [ordered]@{
        parse_status = $payloadFacts.parse_status
        keys = $payloadFacts.keys
        length = $payloadFacts.payload_length
        sha256 = $payloadFacts.payload_sha256
    }
    verification_state = [ordered]@{
        edit_sequence = [int]$state.edit_sequence
        verified_edit_sequence = [int]$state.verified_edit_sequence
        acknowledged_edit_sequence = [int]$state.acknowledged_edit_sequence
        pending = $pendingVerification
    }
    recommendations = $recommendations.ToArray()
}
$entry | ConvertTo-Json -Depth 20 -Compress | Add-Content -LiteralPath $logPath -Encoding UTF8

$summaryLines = @(
    "Last Codex hook: $timestamp",
    "Event: $Event",
    "CWD: $cwd",
    "Decision: $decision",
    "Git dirty: $($gitFacts.dirty)",
    "Changed count: $($gitFacts.changed_count)",
    "Verification pending: $pendingVerification"
)
Set-Content -LiteralPath $latestPath -Value ($summaryLines -join "`r`n") -Encoding UTF8

if ($null -ne $eventOutput) {
    $eventOutput | ConvertTo-Json -Depth 12 -Compress
} elseif ($PassThru -and -not $Quiet) {
    [ordered]@{
        status = "success"
        event = $Event
        decision = $decision
        artifacts = @($logPath, $latestPath)
    } | ConvertTo-Json -Depth 8 -Compress
}
