param(
    [ValidateSet("SessionStart", "SessionEnd", "PreToolUse", "PermissionRequest", "PostToolUse", "PreCompact", "PostCompact", "UserPromptSubmit", "SubagentStart", "SubagentStop", "Stop")]
    [string]$Event = "Stop",
    [string]$Payload = "",
    [string]$CodexHome = "",
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

function Get-GitWorkspaceFingerprint {
    param(
        [string]$Root,
        [int]$MaxChangedPaths = 256,
        [long]$MaxTotalBytes = 16777216,
        [long]$MaxFileBytes = 4194304,
        [int]$MaxStatusChars = 262144
    )

    $result = [ordered]@{
        available = $false
        is_git_repo = $false
        reason = 'not-git'
        repo_key = ''
        fingerprint = ''
        head = ''
        changed_count = 0
        hashed_file_count = 0
        total_bytes = 0
    }

    try {
        $repoRoot = [string](git -C $Root rev-parse --show-toplevel 2>$null)
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repoRoot)) { return [pscustomobject]$result }
        $repoRoot = (Resolve-Path -LiteralPath $repoRoot.Trim()).Path.TrimEnd('\', '/')
        $result.is_git_repo = $true
        $result.repo_key = Get-Sha256Text -Text $repoRoot.ToLowerInvariant()
        $result.head = [string](git -C $repoRoot rev-parse HEAD 2>$null)
        if ($LASTEXITCODE -ne 0) {
            $result.reason = 'git-head-failed'
            return [pscustomobject]$result
        }

        $statusBefore = [string](git -C $repoRoot status --porcelain=v1 -z --untracked-files=all 2>$null)
        if ($LASTEXITCODE -ne 0) {
            $result.reason = 'git-status-failed'
            return [pscustomobject]$result
        }
        if ($statusBefore.Length -gt $MaxStatusChars) {
            $result.reason = 'status-overflow'
            return [pscustomobject]$result
        }

        $tokens = @($statusBefore.Split([char]0) | Where-Object { -not [string]::IsNullOrEmpty($_) })
        $entries = New-Object System.Collections.Generic.List[object]
        for ($index = 0; $index -lt $tokens.Count; $index++) {
            $token = [string]$tokens[$index]
            if ($token.Length -lt 4) {
                $result.reason = 'status-parse-failed'
                return [pscustomobject]$result
            }
            $status = $token.Substring(0, 2)
            $path = $token.Substring(3)
            $originalPath = ''
            if ($status -match '[RC]') {
                $index++
                if ($index -ge $tokens.Count) {
                    $result.reason = 'status-parse-failed'
                    return [pscustomobject]$result
                }
                $originalPath = [string]$tokens[$index]
            }
            $entries.Add([pscustomobject]@{
                status = $status
                path = $path
                original_path = $originalPath
            }) | Out-Null
        }

        $result.changed_count = $entries.Count
        if ($entries.Count -gt $MaxChangedPaths) {
            $result.reason = 'path-overflow'
            return [pscustomobject]$result
        }

        $records = New-Object System.Collections.Generic.List[string]
        $records.Add('schema=codex-git-workspace-fingerprint-v1') | Out-Null
        $records.Add('repo=' + $result.repo_key) | Out-Null
        $records.Add('head=' + $result.head.Trim()) | Out-Null
        $records.Add('changed=' + $entries.Count) | Out-Null
        $observedFiles = New-Object System.Collections.Generic.List[object]

        foreach ($entry in @($entries | Sort-Object path, status)) {
            $relativePath = ([string]$entry.path).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
            $fullPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $relativePath))
            $rootPrefix = $repoRoot + [System.IO.Path]::DirectorySeparatorChar
            if (-not $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $result.reason = 'path-outside-repo'
                return [pscustomobject]$result
            }

            $pathHash = Get-Sha256Text -Text ([string]$entry.path)
            $originalPathHash = Get-Sha256Text -Text ([string]$entry.original_path)
            $indexFacts = [string](git -C $repoRoot ls-files --stage -- ([string]$entry.path) 2>$null)
            if ($LASTEXITCODE -ne 0) {
                $result.reason = 'git-index-failed'
                return [pscustomobject]$result
            }
            $indexHash = Get-Sha256Text -Text $indexFacts

            if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
                $itemBefore = Get-Item -LiteralPath $fullPath -Force
                if ($itemBefore.Length -gt $MaxFileBytes -or ($result.total_bytes + $itemBefore.Length) -gt $MaxTotalBytes) {
                    $result.reason = 'content-overflow'
                    return [pscustomobject]$result
                }
                $contentHash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
                $itemAfter = Get-Item -LiteralPath $fullPath -Force
                if ($itemBefore.Length -ne $itemAfter.Length -or $itemBefore.LastWriteTimeUtc.Ticks -ne $itemAfter.LastWriteTimeUtc.Ticks) {
                    $result.reason = 'workspace-changing'
                    return [pscustomobject]$result
                }
                $result.total_bytes = [long]$result.total_bytes + [long]$itemAfter.Length
                $result.hashed_file_count = [int]$result.hashed_file_count + 1
                $observedFiles.Add([pscustomobject]@{
                    path = $fullPath
                    length = [long]$itemAfter.Length
                    ticks = [long]$itemAfter.LastWriteTimeUtc.Ticks
                }) | Out-Null
                $records.Add("$($entry.status)|$pathHash|$originalPathHash|$indexHash|file|$($itemAfter.Length)|$contentHash") | Out-Null
            } elseif (Test-Path -LiteralPath $fullPath) {
                $result.reason = 'non-file-change'
                return [pscustomobject]$result
            } else {
                $records.Add("$($entry.status)|$pathHash|$originalPathHash|$indexHash|missing") | Out-Null
            }
        }

        $statusAfter = [string](git -C $repoRoot status --porcelain=v1 -z --untracked-files=all 2>$null)
        if ($LASTEXITCODE -ne 0 -or $statusAfter -ne $statusBefore) {
            $result.reason = 'workspace-changing'
            return [pscustomobject]$result
        }
        foreach ($observed in $observedFiles) {
            if (-not (Test-Path -LiteralPath $observed.path -PathType Leaf)) {
                $result.reason = 'workspace-changing'
                return [pscustomobject]$result
            }
            $itemNow = Get-Item -LiteralPath $observed.path -Force
            if ($itemNow.Length -ne $observed.length -or $itemNow.LastWriteTimeUtc.Ticks -ne $observed.ticks) {
                $result.reason = 'workspace-changing'
                return [pscustomobject]$result
            }
        }

        $result.fingerprint = Get-Sha256Text -Text ($records -join "`n")
        $result.available = $true
        $result.reason = 'ok'
    } catch {
        if ($result.reason -eq 'not-git') { $result.reason = 'fingerprint-failed' }
    }

    return [pscustomobject]$result
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

function Get-ToolUseId {
    param([object]$Json)
    if ($null -eq $Json -or -not $Json.tool_use_id) { return '' }
    return [string]$Json.tool_use_id
}

function Get-ToolCommand {
    param([object]$Json)
    if ($null -eq $Json -or $null -eq $Json.tool_input) { return "" }
    foreach ($name in @("command", "cmd", "patch", "input")) {
        if ($Json.tool_input.PSObject.Properties.Name -contains $name) {
            return [string]$Json.tool_input.$name
        }
    }
    return ""
}

function Get-WeeklyRunGuard {
    param(
        [string]$Root,
        [string]$CodexHomePath,
        [string]$SessionKey
    )

    $result = [ordered]@{
        active = $false
        run_id = ""
        caller_cwd = ""
        session_key = ""
        input_path = ""
    }
    $activePath = Join-Path $CodexHomePath "harness-learning\active-run.json"
    if (-not (Test-Path -LiteralPath $activePath -PathType Leaf)) { return [pscustomobject]$result }
    try {
        $active = Get-Content -LiteralPath $activePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $callerCwd = [string]$active.caller_cwd
        $runId = [string]$active.run_id
        $boundSessionKey = if ($active.PSObject.Properties.Name -contains 'session_key') { [string]$active.session_key } else { '' }
        $inputPath = if ($active.PSObject.Properties.Name -contains 'input_path') { [string]$active.input_path } else { '' }
        if ([string]::IsNullOrWhiteSpace($callerCwd) -or [string]::IsNullOrWhiteSpace($runId)) {
            return [pscustomobject]$result
        }

        $sessionMatches = -not [string]::IsNullOrWhiteSpace($boundSessionKey) -and
            -not [string]::IsNullOrWhiteSpace($SessionKey) -and
            $boundSessionKey.Equals($SessionKey, [System.StringComparison]::Ordinal)
        $cwdMatches = $false
        if ([string]::IsNullOrWhiteSpace($boundSessionKey)) {
            $rootPath = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\')
            $callerPath = (Resolve-Path -LiteralPath $callerCwd).Path.TrimEnd('\')
            $cwdMatches = $rootPath.Equals($callerPath, [System.StringComparison]::OrdinalIgnoreCase) -or
                $rootPath.StartsWith($callerPath + '\', [System.StringComparison]::OrdinalIgnoreCase)
        } else {
            $callerPath = (Resolve-Path -LiteralPath $callerCwd).Path.TrimEnd('\')
        }

        if ($sessionMatches -or $cwdMatches) {
            $result.active = $true
            $result.run_id = $runId
            $result.caller_cwd = $callerPath
            $result.session_key = $boundSessionKey
            $result.input_path = $inputPath
        }
    } catch { }
    return [pscustomobject]$result
}

function Set-WeeklyRunMetadata {
    param(
        [string]$CodexHomePath,
        [string]$RunId,
        [string]$SessionKey = '',
        [string]$InputPath = ''
    )

    if ([string]::IsNullOrWhiteSpace($RunId) -or
        ([string]::IsNullOrWhiteSpace($SessionKey) -and [string]::IsNullOrWhiteSpace($InputPath))) {
        return $false
    }
    $activePath = Join-Path $CodexHomePath 'harness-learning\active-run.json'
    if (-not (Test-Path -LiteralPath $activePath -PathType Leaf)) { return $false }

    $mutex = New-Object System.Threading.Mutex($false, ('codex-weekly-run-' + (Get-Sha256Text -Text $RunId).Substring(0, 24)))
    $lockTaken = $false
    try {
        try { $lockTaken = $mutex.WaitOne(2000) } catch { $lockTaken = $false }
        if (-not $lockTaken) { return $false }
        $active = Get-Content -LiteralPath $activePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$active.run_id -ne $RunId) { return $false }

        if (-not [string]::IsNullOrWhiteSpace($SessionKey)) {
            $existingSession = if ($active.PSObject.Properties.Name -contains 'session_key') { [string]$active.session_key } else { '' }
            if (-not [string]::IsNullOrWhiteSpace($existingSession) -and $existingSession -ne $SessionKey) { return $false }
            if ($active.PSObject.Properties.Name -contains 'session_key') {
                $active.session_key = $SessionKey
            } else {
                $active | Add-Member -NotePropertyName session_key -NotePropertyValue $SessionKey
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($InputPath)) {
            $normalizedInput = [System.IO.Path]::GetFullPath($InputPath)
            $existingInput = if ($active.PSObject.Properties.Name -contains 'input_path') { [string]$active.input_path } else { '' }
            if (-not [string]::IsNullOrWhiteSpace($existingInput) -and
                -not ([System.IO.Path]::GetFullPath($existingInput)).Equals($normalizedInput, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $false
            }
            if ($active.PSObject.Properties.Name -contains 'input_path') {
                $active.input_path = $normalizedInput
            } else {
                $active | Add-Member -NotePropertyName input_path -NotePropertyValue $normalizedInput
            }
        }

        $directory = Split-Path -Parent $activePath
        $temporary = Join-Path $directory ('active-run.' + [guid]::NewGuid().ToString('N') + '.tmp')
        try {
            [System.IO.File]::WriteAllText(
                $temporary,
                ($active | ConvertTo-Json -Depth 6),
                (New-Object System.Text.UTF8Encoding($false))
            )
            Move-Item -LiteralPath $temporary -Destination $activePath -Force
        } finally {
            if (Test-Path -LiteralPath $temporary -PathType Leaf) {
                Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
            }
        }
        return $true
    } catch {
        return $false
    } finally {
        if ($lockTaken) {
            try { $mutex.ReleaseMutex() } catch { }
        }
        $mutex.Dispose()
    }
}

function Test-WeeklyStartCommand {
    param([string]$Command, [string]$CodexHomePath)

    if ([string]::IsNullOrWhiteSpace($Command)) { return $false }
    $scriptPath = [regex]::Escape((Join-Path $CodexHomePath 'scripts\invoke-weekly-harness-learning.ps1'))
    $pattern = '^\s*powershell(?:\.exe)?\s+-NoProfile\s+-ExecutionPolicy\s+Bypass\s+-File\s+["'']?' +
        $scriptPath + '["'']?\s+-Mode\s+Start\s*$'
    return [regex]::IsMatch($Command, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

function Get-WeeklyInputPatchPath {
    param([string]$PatchText, [string]$RunId)

    if ([string]::IsNullOrWhiteSpace($PatchText) -or [string]::IsNullOrWhiteSpace($RunId)) { return '' }
    $normalized = $PatchText.Replace("`r`n", "`n").Trim()
    $lines = @($normalized -split "`n")
    if ($lines.Count -lt 4 -or $lines[0] -ne '*** Begin Patch' -or $lines[-1] -ne '*** End Patch') { return '' }
    $headers = @($lines | Where-Object { $_ -match '^\*\*\* (Add|Update|Delete) File: ' })
    if ($headers.Count -ne 1 -or $headers[0] -notmatch '^\*\*\* Add File: (?<path>.+)$') { return '' }
    $candidate = $matches.path.Trim()
    try {
        $candidatePath = [System.IO.Path]::GetFullPath($candidate)
        $tempRoot = [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
    } catch { return '' }
    $expectedPrefix = Join-Path $tempRoot ("codex-weekly-input-$RunId-")
    if (-not $candidatePath.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not $candidatePath.EndsWith('.json', [System.StringComparison]::OrdinalIgnoreCase)) {
        return ''
    }
    for ($index = 2; $index -lt ($lines.Count - 1); $index++) {
        if (-not $lines[$index].StartsWith('+')) { return '' }
    }
    return $candidatePath
}

function Test-WeeklyInputPatch {
    param([string]$PatchText, [string]$RunId)
    return -not [string]::IsNullOrWhiteSpace((Get-WeeklyInputPatchPath -PatchText $PatchText -RunId $RunId))
}

function Test-WeeklyCompleteCommand {
    param(
        [string]$Command,
        [string]$RunId,
        [string]$CodexHomePath,
        [string]$ExpectedInputPath = ''
    )

    if ([string]::IsNullOrWhiteSpace($Command) -or
        [string]::IsNullOrWhiteSpace($RunId) -or
        [string]::IsNullOrWhiteSpace($ExpectedInputPath)) {
        return $false
    }
    $scriptPath = [regex]::Escape((Join-Path $CodexHomePath 'scripts\invoke-weekly-harness-learning.ps1'))
    $run = [regex]::Escape($RunId)
    $pattern = '^\s*powershell(?:\.exe)?\s+-NoProfile\s+-ExecutionPolicy\s+Bypass\s+-File\s+["'']?' +
        $scriptPath + '["'']?\s+-Mode\s+Complete\s+-RunId\s+["'']?' + $run +
        '["'']?\s+-InputPath\s+["'']?(?<input>[^"''\r\n]+)["'']?\s*$'
    $match = [regex]::Match($Command, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) { return $false }
    try {
        $inputPath = [System.IO.Path]::GetFullPath($match.Groups['input'].Value)
        $tempRoot = [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
    } catch { return $false }
    $expectedPrefix = Join-Path $tempRoot ("codex-weekly-input-$RunId-")
    if (-not $inputPath.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not $inputPath.EndsWith('.json', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }
    if (-not $inputPath.Equals([System.IO.Path]::GetFullPath($ExpectedInputPath), [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }
    return Test-Path -LiteralPath $inputPath -PathType Leaf
}

function Test-WeeklyReadOnlyTool {
    param([string]$ToolName)

    if ([string]::IsNullOrWhiteSpace($ToolName)) { return $false }
    $normalized = ($ToolName.Trim().ToLowerInvariant() -replace '[^a-z0-9_]+', '_').Trim('_')
    $allowedTools = @(
        'list_threads',
        'read_thread',
        'codex_app__list_threads',
        'codex_app__read_thread',
        'mcp__threads__list_threads',
        'mcp__threads__read_thread',
        'list_mcp_resource_templates',
        'list_mcp_resources',
        'read_mcp_resource',
        'mcp__exa__web_search_exa',
        'mcp__exa__web_fetch_exa',
        'mcp__context7__resolve_library_id',
        'mcp__context7__query_docs',
        'mcp__openaideveloperdocs__search_openai_docs',
        'mcp__openaideveloperdocs__fetch_openai_doc',
        'mcp__openaideveloperdocs__get_openapi_spec',
        'mcp__openaideveloperdocs__list_openai_docs',
        'read_file',
        'read_text_file',
        'get_file',
        'list_files',
        'find_files',
        'search_files',
        'search_text',
        'view_image'
    )
    return $normalized -in $allowedTools
}

function Get-WeeklyGuardDenyReason {
    param(
        [object]$Guard,
        [string]$ToolName,
        [string]$ToolCommand,
        [string]$CodexHomePath,
        [string]$SessionKey
    )

    if ($null -eq $Guard -or -not [bool]$Guard.active) { return "" }
    if ($ToolName -eq 'Bash') {
        if (Test-WeeklyCompleteCommand -Command $ToolCommand -RunId $Guard.run_id -CodexHomePath $CodexHomePath -ExpectedInputPath $Guard.input_path) { return "" }
        return 'Weekly harness learning is in restricted mode. Shell execution is limited to the exact completion command.'
    }
    if ($ToolName -eq 'apply_patch') {
        $inputPath = Get-WeeklyInputPatchPath -PatchText $ToolCommand -RunId $Guard.run_id
        if (-not [string]::IsNullOrWhiteSpace($inputPath) -and
            (Set-WeeklyRunMetadata -CodexHomePath $CodexHomePath -RunId $Guard.run_id -SessionKey $SessionKey -InputPath $inputPath)) {
            return ""
        }
        return 'Weekly harness learning may use apply_patch only to create its single temporary input JSON under the system TEMP directory.'
    }
    if (Test-WeeklyReadOnlyTool -ToolName $ToolName) { return "" }
    return "Weekly harness learning is in restricted mode. Tool '$ToolName' is outside the read-only intake surface."
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
    $wasV3 = $null -ne $state -and [string]$state.schema -eq 'codex-hook-state-v3'
    if ($null -eq $state) { $state = [pscustomobject]@{} }

    $defaults = [ordered]@{
        schema = 'codex-hook-state-v3'
        session_key = $SessionKey
        edit_sequence = 0
        verified_edit_sequence = 0
        acknowledged_edit_sequence = 0
        stop_continuations = 0
        last_edit_at = ''
        last_verification_at = ''
        last_verification_tool_use_id_sha256 = ''
        last_verified_repo_key = ''
        last_verified_workspace_fingerprint = ''
        acknowledged_repo_key = ''
        acknowledged_workspace_fingerprint = ''
        pending_verifications = @()
        last_fingerprint_status = ''
        last_event = ''
        updated_at = ''
    }
    foreach ($name in $defaults.Keys) {
        if ($state.PSObject.Properties.Name -notcontains $name) {
            $state | Add-Member -NotePropertyName $name -NotePropertyValue $defaults[$name]
        }
    }
    if (-not $wasV3 -and [string]::IsNullOrWhiteSpace([string]$state.last_verified_workspace_fingerprint)) {
        $state.verified_edit_sequence = 0
    }
    $state.pending_verifications = @($state.pending_verifications | Select-Object -Last 8)
    $state.schema = 'codex-hook-state-v3'
    $state.session_key = $SessionKey
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
    $normalized = $Command.Replace("`r", ' ').Replace("`n", ' ').Trim()
    $segment = '(?:^|[;&|]\s*)'
    $scriptLeaf = '(?:[^\\/"'']*[._-])?(?:test|tests|verify|verification|check|lint|build|typecheck)(?:[._-][^\\/"'']*)?\.ps1'
    $patterns = @(
        ('(?i)' + $segment + '(?:&\s*)?(?:powershell(?:\.exe)?|pwsh(?:\.exe)?)\b[^;&|]*?\s-(?:File|f)\s+["'']?(?:[^"'';&|]*[\\/])?' + $scriptLeaf + '["'']?(?:\s|$)'),
        ('(?i)' + $segment + '(?:&\s*)?(?:["''](?:[^"'']*[\\/])?' + $scriptLeaf + '["'']|(?:\.\.?[\\/]|[A-Za-z]:[\\/]|/)(?:[^"'';&|\s]+[\\/])*' + $scriptLeaf + '|' + $scriptLeaf + ')(?:\s|$)'),
        ('(?i)' + $segment + '(?:npm(?:\.cmd)?|pnpm(?:\.cmd)?|yarn(?:\.cmd)?)\s+(?:(?:--?[A-Za-z0-9_.=-]+)\s+)*(?:test(?:\s|$)|run\s+(?:test(?:[:._-][A-Za-z0-9_.-]+)?|verify|check|lint|build|typecheck|e2e)(?:\s|$))'),
        ('(?i)' + $segment + '(?:npx(?:\.cmd)?\s+)?(?:pytest|jest|vitest)(?:\.cmd)?(?:\s|$)'),
        ('(?i)' + $segment + '(?:python(?:\.exe)?|py(?:\.exe)?)(?:\s+-\d+)?\s+-m\s+pytest(?:\s|$)'),
        ('(?i)' + $segment + '(?:npx(?:\.cmd)?\s+)?playwright(?:\.cmd)?\s+test(?:\s|$)'),
        ('(?i)' + $segment + '(?:npx(?:\.cmd)?\s+)?tsc(?:\.cmd)?(?:\s|$)'),
        ('(?i)' + $segment + '(?:cargo\s+test|go\s+test|dotnet\s+test|mvn(?:\.cmd)?\s+test|gradle(?:w)?(?:\.bat)?\s+test)(?:\s|$)'),
        ('(?i)' + $segment + 'git\s+diff(?:\s+[^;&|]*)?\s+--check(?:\s|$)')
    )
    foreach ($pattern in $patterns) {
        if ([regex]::IsMatch($normalized, $pattern)) { return $true }
    }
    return $false
}

function Get-PendingVerification {
    param([object]$State, [string]$ToolUseId)

    if ([string]::IsNullOrWhiteSpace($ToolUseId)) { return $null }
    $toolUseHash = Get-Sha256Text -Text $ToolUseId
    return @($State.pending_verifications | Where-Object {
        [string]$_.tool_use_id_sha256 -eq $toolUseHash
    } | Select-Object -Last 1)[0]
}

function Set-PendingVerification {
    param(
        [object]$State,
        [string]$ToolUseId,
        [object]$Fingerprint,
        [string]$Timestamp
    )

    if ([string]::IsNullOrWhiteSpace($ToolUseId) -or $null -eq $Fingerprint -or -not [bool]$Fingerprint.available) {
        return $false
    }
    $toolUseHash = Get-Sha256Text -Text $ToolUseId
    $pending = @($State.pending_verifications | Where-Object {
        [string]$_.tool_use_id_sha256 -ne $toolUseHash
    })
    $pending += [pscustomobject]@{
        tool_use_id_sha256 = $toolUseHash
        repo_key = [string]$Fingerprint.repo_key
        workspace_fingerprint = [string]$Fingerprint.fingerprint
        edit_sequence = [int]$State.edit_sequence
        started_at = $Timestamp
    }
    $State.pending_verifications = @($pending | Select-Object -Last 8)
    return $true
}

function Remove-PendingVerification {
    param([object]$State, [string]$ToolUseId)

    if ([string]::IsNullOrWhiteSpace($ToolUseId)) { return }
    $toolUseHash = Get-Sha256Text -Text $ToolUseId
    $State.pending_verifications = @($State.pending_verifications | Where-Object {
        [string]$_.tool_use_id_sha256 -ne $toolUseHash
    })
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

if ([string]::IsNullOrWhiteSpace($CodexHome)) {
    $CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
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
$toolUseId = Get-ToolUseId -Json $payloadJson
$toolCommand = Get-ToolCommand -Json $payloadJson
$sessionKey = Get-SessionKey -Json $payloadJson -Root $cwd
$weeklyGuard = Get-WeeklyRunGuard -Root $cwd -CodexHomePath $codexHomePath -SessionKey $sessionKey
if ($Event -eq 'PostToolUse' -and $toolName -eq 'Bash' -and
    (Test-ToolSucceeded -Json $payloadJson) -and
    (Test-WeeklyStartCommand -Command $toolCommand -CodexHomePath $codexHomePath) -and
    -not [string]::IsNullOrWhiteSpace([string]$weeklyGuard.run_id)) {
    if (Set-WeeklyRunMetadata -CodexHomePath $codexHomePath -RunId $weeklyGuard.run_id -SessionKey $sessionKey) {
        $weeklyGuard = Get-WeeklyRunGuard -Root $cwd -CodexHomePath $codexHomePath -SessionKey $sessionKey
    }
}
$statePath = Join-Path $LogRoot ("state\" + $sessionKey + ".json")
$eventOutput = if ($Event -in @("SubagentStop", "Stop")) { [ordered]@{} } else { $null }
$decision = "observe"
$recommendations = New-Object System.Collections.Generic.List[string]

if ($Event -in @("PreToolUse", "PermissionRequest") -and [bool]$weeklyGuard.active) {
    $weeklyDenyReason = Get-WeeklyGuardDenyReason `
        -Guard $weeklyGuard `
        -ToolName $toolName `
        -ToolCommand $toolCommand `
        -CodexHomePath $codexHomePath `
        -SessionKey $sessionKey
    if ($weeklyDenyReason) {
        $decision = "deny"
        if ($Event -eq "PreToolUse") {
            $eventOutput = [ordered]@{
                systemMessage = $weeklyDenyReason
                hookSpecificOutput = [ordered]@{
                    hookEventName = "PreToolUse"
                    permissionDecision = "deny"
                    permissionDecisionReason = $weeklyDenyReason
                }
            }
        } else {
            $eventOutput = [ordered]@{
                systemMessage = $weeklyDenyReason
                hookSpecificOutput = [ordered]@{
                    hookEventName = "PermissionRequest"
                    decision = [ordered]@{ behavior = "deny"; message = $weeklyDenyReason }
                }
            }
        }
    }
}

if ($decision -ne "deny" -and $Event -in @("PreToolUse", "PermissionRequest") -and $toolName -eq "Bash") {
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
$workspaceFingerprint = $null
$fingerprintPending = $false
$sequencePending = $false
$pendingVerification = $false
$stateWriteSucceeded = $false
try {
    $mutex = New-Object System.Threading.Mutex($false, ("codex-hook-state-" + $sessionKey))
    try { $lockTaken = $mutex.WaitOne(2000) } catch { $lockTaken = $false }
    $state = Read-HookState -Path $statePath -SessionKey $sessionKey

    if (-not $lockTaken) {
        if ($decision -eq 'observe') { $decision = 'state-lock-degraded' }
        $recommendations.Add('Hook state lock was unavailable; this observational event did not mutate shared verification state.') | Out-Null
    } else {
        if ($Event -eq 'PreToolUse' -and $decision -ne 'deny' -and $toolName -eq 'Bash' -and
            (Test-VerificationCommand -Command $toolCommand)) {
            $workspaceFingerprint = Get-GitWorkspaceFingerprint -Root $cwd
            $state.last_fingerprint_status = [string]$workspaceFingerprint.reason
            if (Set-PendingVerification -State $state -ToolUseId $toolUseId -Fingerprint $workspaceFingerprint -Timestamp $timestamp) {
                $decision = 'verification-started'
            } else {
                $decision = if ([string]::IsNullOrWhiteSpace($toolUseId)) { 'verification-missing-tool-use-id' } else { 'verification-fingerprint-unavailable' }
            }
        }

        if ($Event -eq 'PostToolUse') {
            $toolSucceeded = Test-ToolSucceeded -Json $payloadJson
            $isWeeklyInputWrite = [bool]$weeklyGuard.active -and $toolName -eq 'apply_patch' -and
                (Test-WeeklyInputPatch -PatchText $toolCommand -RunId $weeklyGuard.run_id)
            if ($toolSucceeded -and (Test-WriteTool -ToolName $toolName -Command $toolCommand) -and -not $isWeeklyInputWrite) {
                $state.edit_sequence = [int]$state.edit_sequence + 1
                $state.stop_continuations = 0
                $state.last_edit_at = $timestamp
                $decision = 'edit-observed'
            }

            if ($toolName -eq 'Bash' -and (Test-VerificationCommand -Command $toolCommand)) {
                $pending = Get-PendingVerification -State $state -ToolUseId $toolUseId
                if ($null -eq $pending) {
                    $decision = 'verification-unpaired'
                } elseif (-not $toolSucceeded -or $null -eq $payloadJson -or $null -eq $payloadJson.tool_response) {
                    $decision = 'verification-failed'
                } else {
                    $workspaceFingerprint = Get-GitWorkspaceFingerprint -Root $cwd
                    $state.last_fingerprint_status = [string]$workspaceFingerprint.reason
                    $stableFingerprint = [bool]$workspaceFingerprint.available -and
                        [string]$pending.repo_key -eq [string]$workspaceFingerprint.repo_key -and
                        [string]$pending.workspace_fingerprint -eq [string]$workspaceFingerprint.fingerprint -and
                        [int]$pending.edit_sequence -eq [int]$state.edit_sequence
                    if ($stableFingerprint) {
                        $state.verified_edit_sequence = [int]$state.edit_sequence
                        $state.stop_continuations = 0
                        $state.last_verification_at = $timestamp
                        $state.last_verification_tool_use_id_sha256 = Get-Sha256Text -Text $toolUseId
                        $state.last_verified_repo_key = [string]$workspaceFingerprint.repo_key
                        $state.last_verified_workspace_fingerprint = [string]$workspaceFingerprint.fingerprint
                        $state.acknowledged_repo_key = ''
                        $state.acknowledged_workspace_fingerprint = ''
                        $decision = 'verification-observed'
                    } else {
                        $decision = 'verification-stale'
                    }
                }
                Remove-PendingVerification -State $state -ToolUseId $toolUseId
            }
        }

        if ($Event -eq 'SessionStart' -and $projectFacts.current_session_summary) {
            $eventOutput = New-AdditionalContextOutput -EventName $Event -Context "A durable session summary exists at $($projectFacts.current_session_summary). Read it only when resuming related work."
        }

        if ($Event -eq 'PreCompact') {
            $recommendations.Add('Preserve the objective, decisions, verification evidence, and next action before compaction when the task spans context windows.') | Out-Null
        }

        if ($Event -eq 'SubagentStart') {
            $eventOutput = New-AdditionalContextOutput -EventName $Event -Context 'Keep the delegated scope bounded. Return ownership, changed files, checks, risks, and unresolved work; do not return raw logs.'
        }

        if ($Event -eq 'Stop') {
            $workspaceFingerprint = Get-GitWorkspaceFingerprint -Root $cwd
            $state.last_fingerprint_status = [string]$workspaceFingerprint.reason
            $pendingFloor = [math]::Max([int]$state.verified_edit_sequence, [int]$state.acknowledged_edit_sequence)
            $sequencePending = [int]$state.edit_sequence -gt $pendingFloor

            if (-not [string]::IsNullOrWhiteSpace([string]$state.last_verified_workspace_fingerprint)) {
                $coveredByVerification = [bool]$workspaceFingerprint.available -and
                    [string]$workspaceFingerprint.repo_key -eq [string]$state.last_verified_repo_key -and
                    [string]$workspaceFingerprint.fingerprint -eq [string]$state.last_verified_workspace_fingerprint
                $coveredByAcknowledgement = [bool]$workspaceFingerprint.available -and
                    [string]$workspaceFingerprint.repo_key -eq [string]$state.acknowledged_repo_key -and
                    [string]$workspaceFingerprint.fingerprint -eq [string]$state.acknowledged_workspace_fingerprint
                $fingerprintPending = -not ($coveredByVerification -or $coveredByAcknowledgement)
            } elseif ([int]$state.verified_edit_sequence -gt 0) {
                $fingerprintPending = $true
            }
            $pendingVerification = $sequencePending -or $fingerprintPending
            $stopHookActive = $false
            if ($null -ne $payloadJson -and $payloadJson.stop_hook_active) { $stopHookActive = [bool]$payloadJson.stop_hook_active }

            if ($pendingVerification -and -not $stopHookActive -and [int]$state.stop_continuations -lt 1) {
                $state.stop_continuations = [int]$state.stop_continuations + 1
                $decision = 'continue-for-verification'
                $eventOutput = [ordered]@{
                    decision = 'block'
                    reason = 'Tracked or current workspace edits are not covered by a causally matched verification fingerprint. Run the smallest meaningful check, then report the evidence or a precise blocker.'
                }
            } elseif ($pendingVerification) {
                $state.acknowledged_edit_sequence = [int]$state.edit_sequence
                if ([bool]$workspaceFingerprint.available) {
                    $state.acknowledged_repo_key = [string]$workspaceFingerprint.repo_key
                    $state.acknowledged_workspace_fingerprint = [string]$workspaceFingerprint.fingerprint
                }
                $decision = 'unverified-acknowledged'
                $eventOutput = [ordered]@{}
            }
        }

        $state.last_event = $Event
        Write-HookState -Path $statePath -State $state
        $stateWriteSucceeded = $true
    }
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
$sequencePending = [int]$state.edit_sequence -gt $pendingFloor
$pendingVerification = $sequencePending -or $fingerprintPending
$logPath = Join-Path $LogRoot ("hook-" + $Event.ToLowerInvariant() + "-" + $date + ".jsonl")
$latestPath = if ($Event -eq "Stop") { Join-Path $LogRoot "latest-stop.txt" } else { Join-Path $LogRoot "latest-hook.txt" }
$entry = [ordered]@{
    schema = 'codex-hook-event-v3'
    ts = $timestamp
    event = $Event
    cwd = $cwd
    decision = $decision
    tool_name = $toolName
    tool_use_id_sha256 = Get-Sha256Text -Text $toolUseId
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
        state_lock_acquired = $lockTaken
        state_write_succeeded = $stateWriteSucceeded
        edit_sequence = [int]$state.edit_sequence
        verified_edit_sequence = [int]$state.verified_edit_sequence
        acknowledged_edit_sequence = [int]$state.acknowledged_edit_sequence
        pending_invocation_count = @($state.pending_verifications).Count
        last_verified_repo_key = [string]$state.last_verified_repo_key
        last_verified_workspace_fingerprint = [string]$state.last_verified_workspace_fingerprint
        current_workspace_fingerprint = if ($null -ne $workspaceFingerprint -and [bool]$workspaceFingerprint.available) { [string]$workspaceFingerprint.fingerprint } else { '' }
        fingerprint_status = if ($null -ne $workspaceFingerprint) { [string]$workspaceFingerprint.reason } else { [string]$state.last_fingerprint_status }
        sequence_pending = $sequencePending
        fingerprint_pending = $fingerprintPending
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
