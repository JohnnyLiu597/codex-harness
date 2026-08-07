param(
    [string]$CodexHome = "$env:USERPROFILE\.codex",
    [string]$PromptFile = "",
    [switch]$DryRun,
    [switch]$IncludeDisabled,
    [int]$Limit = 0,
    [switch]$NoGrade,
    [switch]$AllowFailures,
    [string]$RunsRoot = "",
    [string]$CodexCommand = "",
    [ValidateRange(1, 86400)][int]$TimeoutSeconds = 300,
    [ValidateRange(1, 10)][int]$Attempts = 1
)

$ErrorActionPreference = "Stop"

function Get-FileEvidence {
    param([string]$Path)

    $exists = -not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path -PathType Leaf)
    return [ordered]@{
        path = $Path
        exists = [bool]$exists
        bytes = if ($exists) { (Get-Item -LiteralPath $Path).Length } else { 0 }
        sha256 = if ($exists) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() } else { "" }
    }
}

function Get-StringSha256 {
    param([AllowEmptyString()][string]$Value)

    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Value)
        return ([System.BitConverter]::ToString($algorithm.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
    } finally {
        $algorithm.Dispose()
    }
}

function Split-Terms {
    param([object]$Value)

    $terms = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Value)) {
        if ($null -eq $item) { continue }
        foreach ($term in ([string]$item -split '\|')) {
            if (-not [string]::IsNullOrWhiteSpace($term)) {
                $terms.Add($term.Trim()) | Out-Null
            }
        }
    }
    return $terms.ToArray()
}

function Get-ObjectPropertyValue {
    param(
        [object]$Object,
        [string[]]$Names,
        [object]$Default = $null
    )

    if ($null -eq $Object) { return $Default }
    foreach ($name in $Names) {
        if ($Object.PSObject.Properties.Name -contains $name) {
            $value = $Object.$name
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
                return $value
            }
        }
    }
    return $Default
}

function Get-BoundedCaseInteger {
    param(
        [object]$Case,
        [string[]]$Names,
        [int]$Default,
        [int]$Minimum,
        [int]$Maximum
    )

    $raw = Get-ObjectPropertyValue -Object $Case -Names $Names -Default $Default
    $parsed = 0
    if (-not [int]::TryParse([string]$raw, [ref]$parsed)) { return $Default }
    if ($parsed -lt $Minimum) { return $Minimum }
    if ($parsed -gt $Maximum) { return $Maximum }
    return $parsed
}

function Get-EnvironmentEvidence {
    param([bool]$CodexAvailable)

    $names = @(Get-ChildItem Env: | Select-Object -ExpandProperty Name)
    $proxyCount = @($names | Where-Object { $_ -match '(?i)proxy' }).Count
    $authCount = @($names | Where-Object { $_ -match '(?i)(auth|token|secret|password|passwd|api[_-]?key|credential)' }).Count
    return [ordered]@{
        platform = [System.Environment]::OSVersion.Platform.ToString()
        os_version = [System.Environment]::OSVersion.VersionString
        powershell_version = $PSVersionTable.PSVersion.ToString()
        powershell_edition = [string]$PSVersionTable.PSEdition
        process_bitness = if ([System.Environment]::Is64BitProcess) { 64 } else { 32 }
        ci_present = [bool]($names -contains "CI")
        codex_available = $CodexAvailable
        proxy_variables_present = [bool]($proxyCount -gt 0)
        proxy_variable_count = $proxyCount
        auth_like_variables_present = [bool]($authCount -gt 0)
        auth_like_variable_count = $authCount
        environment_values_recorded = $false
    }
}

function New-RunId {
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssfffZ")
    $nonce = [guid]::NewGuid().ToString("N").Substring(0, 12)
    return "$stamp-$PID-$nonce"
}

function Resolve-CodexCommand {
    param([string]$ExplicitPath)

    $candidates = New-Object System.Collections.Generic.List[string]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        $resolved = (Resolve-Path -LiteralPath $ExplicitPath -ErrorAction Stop).Path
        if ($seen.Add($resolved)) { $candidates.Add($resolved) | Out-Null }
    }

    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $localBinary = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin\codex.exe'
        if ((Test-Path -LiteralPath $localBinary -PathType Leaf) -and $seen.Add($localBinary)) {
            $candidates.Add($localBinary) | Out-Null
        }
    }

    foreach ($command in @(Get-Command codex -All -ErrorAction SilentlyContinue)) {
        $source = if ($command.Path) { [string]$command.Path } else { [string]$command.Source }
        if (-not [string]::IsNullOrWhiteSpace($source) -and $seen.Add($source)) {
            $candidates.Add($source) | Out-Null
        }
    }

    foreach ($candidate in $candidates) {
        try {
            $version = (& $candidate --version 2>&1 | Out-String).Trim()
            if ($LASTEXITCODE -eq 0) {
                return [pscustomobject]@{ Source = $candidate; Version = $version }
            }
        } catch { }
    }
    return $null
}

function ConvertTo-NativeArgument {
    param([AllowEmptyString()][string]$Value)

    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
    $escaped = $Value -replace '(\\*)"', '$1$1\"'
    $escaped = $escaped -replace '(\\+)$', '$1$1'
    return '"' + $escaped + '"'
}

function Get-ProcessLaunch {
    param(
        [Parameter(Mandatory = $true)][string]$CommandPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $extension = [System.IO.Path]::GetExtension($CommandPath).ToLowerInvariant()
    if ($extension -eq ".ps1") {
        $hostCommand = Get-Command powershell.exe -ErrorAction Stop
        $allArguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $CommandPath) + $Arguments
        return [pscustomobject]@{
            file_name = $hostCommand.Source
            arguments = (($allArguments | ForEach-Object { ConvertTo-NativeArgument -Value $_ }) -join ' ')
        }
    }
    if ($extension -in @(".cmd", ".bat")) {
        $allArguments = (($Arguments | ForEach-Object { ConvertTo-NativeArgument -Value $_ }) -join ' ')
        $commandLine = '"' + $CommandPath + '"' + $(if ($allArguments) { " $allArguments" } else { "" })
        return [pscustomobject]@{
            file_name = $env:ComSpec
            arguments = '/d /s /c "' + $commandLine + '"'
        }
    }
    return [pscustomobject]@{
        file_name = $CommandPath
        arguments = (($Arguments | ForEach-Object { ConvertTo-NativeArgument -Value $_ }) -join ' ')
    }
}

function Add-UniqueValue {
    param(
        [System.Collections.Generic.List[string]]$Values,
        [System.Collections.Generic.HashSet[string]]$Seen,
        [object]$Value
    )

    if ($null -eq $Value) { return }
    $text = ([string]$Value).Trim()
    if (-not [string]::IsNullOrWhiteSpace($text) -and $Seen.Add($text)) {
        $Values.Add($text) | Out-Null
    }
}

function Test-IgnorableTraceNoise {
    param([string]$Line)

    if ($Line -match '^SUCCESS: The process with PID [0-9]+ \(child process of PID [0-9]+\) has been terminated\.$') { return $true }
    if ($Line.Length -gt 200 -or $Line -match '[\{\}\[\]"]') { return $false }
    $decodedSuccess = $Line.Length -ge 2 -and [int][char]$Line[0] -eq 0x6210 -and [int][char]$Line[1] -eq 0x529f
    $garbledSuccess = $Line.Length -ge 1 -and [int][char]$Line[0] -eq 0xfffd
    if (-not ($decodedSuccess -or $garbledSuccess)) { return $false }
    return [bool]($Line -match '^[^\x00-\x7F]{1,8}: [^A-Za-z\r\n]*PID [0-9]+ \([^A-Za-z\r\n]*PID [0-9]+[^A-Za-z\r\n]*\)[^A-Za-z\r\n]*$')
}

function Read-CodexExecTrace {
    param([string]$TracePath)

    $eventTypes = New-Object System.Collections.Generic.List[string]
    $eventSeen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $toolNames = New-Object System.Collections.Generic.List[string]
    $toolSeen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $finalAssistantMessage = ""
    $assistantMessageCount = 0
    $jsonLineCount = 0
    $invalidJsonLineCount = 0
    $ignoredProcessCleanupLineCount = 0
    $errorEventCount = 0

    if (Test-Path -LiteralPath $TracePath -PathType Leaf) {
        foreach ($line in Get-Content -LiteralPath $TracePath -ErrorAction SilentlyContinue) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if (Test-IgnorableTraceNoise -Line ([string]$line)) {
                $ignoredProcessCleanupLineCount++
                continue
            }
            $jsonLineCount++
            try {
                $event = $line | ConvertFrom-Json
            } catch {
                $invalidJsonLineCount++
                continue
            }

            $eventType = [string](Get-ObjectPropertyValue -Object $event -Names @("type") -Default "")
            Add-UniqueValue -Values $eventTypes -Seen $eventSeen -Value $eventType
            if ($eventType -in @("error", "turn.failed")) { $errorEventCount++ }

            $item = Get-ObjectPropertyValue -Object $event -Names @("item") -Default $null
            if ($null -eq $item) { continue }
            $itemType = [string](Get-ObjectPropertyValue -Object $item -Names @("type") -Default "")

            if ($eventType -eq "item.completed" -and $itemType -in @("agent_message", "assistant_message")) {
                $text = [string](Get-ObjectPropertyValue -Object $item -Names @("text", "message", "content") -Default "")
                $finalAssistantMessage = $text
                $assistantMessageCount++
            }

            if ($itemType -in @("command_execution", "file_change", "mcp_tool_call", "web_search", "plan_update", "tool_call", "function_call")) {
                Add-UniqueValue -Values $toolNames -Seen $toolSeen -Value $itemType
            }
            $toolName = Get-ObjectPropertyValue -Object $item -Names @("tool_name", "name", "tool") -Default $null
            if ($toolName -is [string]) {
                Add-UniqueValue -Values $toolNames -Seen $toolSeen -Value $toolName
            }
            if ($itemType -eq "mcp_tool_call") {
                $serverName = [string](Get-ObjectPropertyValue -Object $item -Names @("server", "server_name") -Default "")
                if (-not [string]::IsNullOrWhiteSpace($serverName) -and $toolName -is [string]) {
                    Add-UniqueValue -Values $toolNames -Seen $toolSeen -Value "mcp:$serverName/$toolName"
                }
            }
        }
    }

    return [pscustomobject]@{
        event_types = $eventTypes.ToArray()
        tool_names = $toolNames.ToArray()
        final_assistant_message = $finalAssistantMessage
        final_assistant_sha256 = if ($assistantMessageCount -gt 0) { Get-StringSha256 -Value $finalAssistantMessage } else { "" }
        final_assistant_bytes = if ($assistantMessageCount -gt 0) { [System.Text.Encoding]::UTF8.GetByteCount($finalAssistantMessage) } else { 0 }
        assistant_message_count = $assistantMessageCount
        json_line_count = $jsonLineCount
        invalid_json_line_count = $invalidJsonLineCount
        ignored_process_cleanup_line_count = $ignoredProcessCleanupLineCount
        error_event_count = $errorEventCount
    }
}

function Get-SafeTraceSummary {
    param([object]$TraceSummary)

    return [ordered]@{
        event_types = @($TraceSummary.event_types)
        tool_names = @($TraceSummary.tool_names)
        final_assistant_sha256 = [string]$TraceSummary.final_assistant_sha256
        final_assistant_bytes = [int]$TraceSummary.final_assistant_bytes
        assistant_message_count = [int]$TraceSummary.assistant_message_count
        json_line_count = [int]$TraceSummary.json_line_count
        invalid_json_line_count = [int]$TraceSummary.invalid_json_line_count
        ignored_process_cleanup_line_count = [int]$TraceSummary.ignored_process_cleanup_line_count
        error_event_count = [int]$TraceSummary.error_event_count
        raw_event_payloads_recorded = $false
    }
}

function Stop-ProcessTree {
    param([int]$ProcessId)

    if ($ProcessId -le 0 -or -not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { return "not-needed" }

    $taskkill = Get-Command taskkill.exe -ErrorAction SilentlyContinue
    if ($taskkill) {
        & $taskkill.Source /PID $ProcessId /T /F 2>$null | Out-Null
        Start-Sleep -Milliseconds 100
        if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { return "terminated" }
    }

    try {
        Stop-Process -Id $ProcessId -Force -ErrorAction Stop
        Start-Sleep -Milliseconds 100
    } catch { }
    return $(if (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) { "failed" } else { "terminated" })
}

function Invoke-CodexAttempt {
    param(
        [Parameter(Mandatory = $true)][object]$Codex,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$AttemptId,
        [Parameter(Mandatory = $true)][string]$CaseId,
        [Parameter(Mandatory = $true)][int]$AttemptNumber,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds,
        [Parameter(Mandatory = $true)][string]$TracePath,
        [Parameter(Mandatory = $true)][string]$StderrPath,
        [Parameter(Mandatory = $true)][string]$FinalPath
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $status = "failed"
    $failureClass = "process-start"
    $message = "Codex process did not start."
    $exitCode = $null
    $processId = 0
    $timedOut = $false
    $childTreeCleanup = "not-needed"
    $process = $null
    $stdoutTask = $null
    $stderrTask = $null

    Set-Content -LiteralPath $TracePath -Value "" -Encoding UTF8
    Set-Content -LiteralPath $StderrPath -Value "" -Encoding UTF8
    Set-Content -LiteralPath $FinalPath -Value "" -Encoding UTF8

    try {
        $codexArguments = @(
            "exec",
            "--json",
            "--ephemeral",
            "--color", "never",
            "--skip-git-repo-check",
            "--cd", $WorkingDirectory,
            "-"
        )
        $launch = Get-ProcessLaunch -CommandPath ([string]$Codex.Source) -Arguments $codexArguments
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $launch.file_name
        $startInfo.Arguments = $launch.arguments
        $startInfo.WorkingDirectory = $WorkingDirectory
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.EnvironmentVariables["CODEX_TRACE_EVAL_ATTEMPT"] = [string]$AttemptNumber
        $startInfo.EnvironmentVariables["CODEX_TRACE_EVAL_CASE_ID"] = $CaseId

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        if (-not $process.Start()) { throw "Codex process start returned false." }
        $processId = $process.Id
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.StandardInput.Write($Prompt)
        $process.StandardInput.Close()

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $timedOut = $true
            $failureClass = "timeout"
            $message = "Codex exec exceeded the per-case timeout."
            $childTreeCleanup = Stop-ProcessTree -ProcessId $processId
            if (-not $process.HasExited) { $process.WaitForExit(3000) | Out-Null }
        } else {
            $process.WaitForExit()
        }

        if ($process.HasExited) { $exitCode = $process.ExitCode }
        $stdout = if ($stdoutTask -and $stdoutTask.Wait(3000)) { [string]$stdoutTask.Result } else { "" }
        $stderr = if ($stderrTask -and $stderrTask.Wait(3000)) { [string]$stderrTask.Result } else { "" }
        Set-Content -LiteralPath $TracePath -Value $stdout -Encoding UTF8 -NoNewline
        Set-Content -LiteralPath $StderrPath -Value $stderr -Encoding UTF8 -NoNewline

        $traceSummary = Read-CodexExecTrace -TracePath $TracePath
        if ($traceSummary.assistant_message_count -gt 0) {
            Set-Content -LiteralPath $FinalPath -Value $traceSummary.final_assistant_message -Encoding UTF8 -NoNewline
        }

        if (-not $timedOut) {
            if ($null -eq $exitCode -or $exitCode -ne 0) {
                $failureClass = "nonzero-exit"
                $message = "Codex exec returned a nonzero exit code."
            } elseif ($traceSummary.invalid_json_line_count -gt 0) {
                $failureClass = "invalid-jsonl"
                $message = "Codex exec emitted invalid JSONL."
            } elseif ($traceSummary.error_event_count -gt 0) {
                $failureClass = "trace-error"
                $message = "Codex exec emitted an error event."
            } elseif ($traceSummary.assistant_message_count -eq 0) {
                $failureClass = "missing-final-assistant"
                $message = "Codex exec emitted no completed assistant message."
            } else {
                $status = "completed"
                $failureClass = "none"
                $message = ""
            }
        }
    } catch {
        if ($failureClass -eq "process-start") { $message = "Codex process could not be started." }
    } finally {
        if ($process -and -not $process.HasExited) {
            $cleanupResult = Stop-ProcessTree -ProcessId $process.Id
            if ($childTreeCleanup -eq "not-needed") { $childTreeCleanup = $cleanupResult }
        }
        if ($process) { $process.Dispose() }
        $stopwatch.Stop()
    }

    $traceSummary = Read-CodexExecTrace -TracePath $TracePath
    return [pscustomobject]@{
        schema = "codex-trace-attempt-v3"
        attempt_id = $AttemptId
        attempt = $AttemptNumber
        status = $status
        failure_class = $failureClass
        message = $message
        exit_code = $exitCode
        timed_out = $timedOut
        timeout_seconds = $TimeoutSeconds
        duration_ms = [int][Math]::Round($stopwatch.Elapsed.TotalMilliseconds)
        process_id = $processId
        child_tree_cleanup = $childTreeCleanup
        trace = $TracePath
        stderr = $StderrPath
        final = $FinalPath
        trace_summary = Get-SafeTraceSummary -TraceSummary $traceSummary
        artifacts = [ordered]@{
            trace = Get-FileEvidence -Path $TracePath
            stderr = Get-FileEvidence -Path $StderrPath
            final = Get-FileEvidence -Path $FinalPath
        }
    }
}

$runStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$codexHomePath = (Resolve-Path -LiteralPath $CodexHome).Path
if (-not $PromptFile) {
    $PromptFile = Join-Path $codexHomePath "harness-evals\trace-evals\prompts.csv"
}
if (-not (Test-Path -LiteralPath $PromptFile -PathType Leaf)) {
    throw "Prompt file not found: $PromptFile"
}
$PromptFile = (Resolve-Path -LiteralPath $PromptFile).Path

if (-not $RunsRoot) {
    $RunsRoot = Join-Path $codexHomePath "harness-evals\trace-evals\runs"
}
New-Item -ItemType Directory -Force -Path $RunsRoot | Out-Null
$RunsRoot = (Resolve-Path -LiteralPath $RunsRoot).Path

$runId = New-RunId
$runDir = Join-Path $RunsRoot $runId
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$resultManifestPath = Join-Path $runDir "evals.json"
$gradeManifestPath = Join-Path $runDir "grades.json"
$summaryPath = Join-Path $runDir "summary.md"
$gradeScript = Join-Path $codexHomePath "harness-evals\grade-trace-evals.ps1"
$codex = Resolve-CodexCommand -ExplicitPath $CodexCommand

$runner = [ordered]@{
    name = "global-trace-runner"
    version = "3.0"
    script = Get-FileEvidence -Path $PSCommandPath
    command = "codex exec --json --ephemeral"
    codex_available = [bool]$codex
    codex_command_path = if ($codex) { $codex.Source } else { "" }
    codex_version = if ($codex) { $codex.Version } else { "" }
    default_timeout_seconds = $TimeoutSeconds
    default_attempts = $Attempts
    prompt_transport = "stdin"
}
$grader = [ordered]@{
    name = "global-trace-grader"
    enabled = -not [bool]$NoGrade
    allow_failures = [bool]$AllowFailures
    script = Get-FileEvidence -Path $gradeScript
}
$environment = Get-EnvironmentEvidence -CodexAvailable ([bool]$codex)
$promptFileEvidence = Get-FileEvidence -Path $PromptFile

$cases = @(Import-Csv -LiteralPath $PromptFile)
if (-not $IncludeDisabled) {
    $cases = @($cases | Where-Object { ([string]$_.enabled).ToLowerInvariant() -eq "true" })
}
if ($Limit -gt 0) {
    $cases = @($cases | Select-Object -First $Limit)
}

$results = New-Object System.Collections.Generic.List[object]
$caseNumber = 0

foreach ($case in $cases) {
    $caseNumber++
    $caseStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $sourceId = [string]$case.id
    $caseSlug = ($sourceId -replace '[^A-Za-z0-9_.-]', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($caseSlug)) { $caseSlug = "case-$caseNumber" }
    $caseId = ("{0:D3}-{1}" -f $caseNumber, $caseSlug)
    $caseDir = Join-Path $runDir $caseId
    New-Item -ItemType Directory -Force -Path $caseDir | Out-Null

    $caseResultPath = Join-Path $caseDir "result.json"
    $caseGradePath = Join-Path $caseDir "grade.json"
    $promptText = [string]$case.prompt
    $expectedText = [string]$case.expected
    $mustInclude = @(Split-Terms -Value $case.must_include)
    $mustNotInclude = @(Split-Terms -Value $case.must_not_include)
    $mustIncludeEvents = @(Split-Terms -Value (Get-ObjectPropertyValue -Object $case -Names @("must_include_events", "required_events") -Default ""))
    $mustNotIncludeEvents = @(Split-Terms -Value (Get-ObjectPropertyValue -Object $case -Names @("must_not_include_events", "prohibited_events") -Default ""))
    $mustIncludeTools = @(Split-Terms -Value (Get-ObjectPropertyValue -Object $case -Names @("must_include_tools", "required_tools") -Default ""))
    $mustNotIncludeTools = @(Split-Terms -Value (Get-ObjectPropertyValue -Object $case -Names @("must_not_include_tools", "prohibited_tools") -Default ""))
    $minScore = Get-BoundedCaseInteger -Case $case -Names @("min_score") -Default 70 -Minimum 0 -Maximum 100
    $caseTimeoutSeconds = Get-BoundedCaseInteger -Case $case -Names @("timeout_seconds", "timeout") -Default $TimeoutSeconds -Minimum 1 -Maximum 86400
    $caseMaxAttempts = Get-BoundedCaseInteger -Case $case -Names @("attempts", "max_attempts") -Default $Attempts -Minimum 1 -Maximum 10
    $promptSha256 = Get-StringSha256 -Value $promptText
    $expectedSha256 = Get-StringSha256 -Value $expectedText
    $lane = [string](Get-ObjectPropertyValue -Object $case -Names @("lane", "kind") -Default "")
    $attemptRecords = New-Object System.Collections.Generic.List[object]
    $selectedAttempt = $null

    if ($DryRun -or -not $codex) {
        $syntheticStatus = if ($DryRun) { "dry-run" } else { "skipped-no-codex" }
        $attemptDir = Join-Path $caseDir "attempt-00"
        New-Item -ItemType Directory -Force -Path $attemptDir | Out-Null
        $tracePath = Join-Path $attemptDir "trace.jsonl"
        $stderrPath = Join-Path $attemptDir "stderr.txt"
        $finalPath = Join-Path $attemptDir "final.txt"
        [ordered]@{
            schema = "codex-trace-event-v3"
            type = $syntheticStatus
            case_id = $sourceId
            prompt_sha256 = $promptSha256
            expected_sha256 = $expectedSha256
            execution_attempted = $false
        } | ConvertTo-Json -Depth 5 -Compress | Set-Content -LiteralPath $tracePath -Encoding UTF8
        Set-Content -LiteralPath $stderrPath -Value "" -Encoding UTF8
        Set-Content -LiteralPath $finalPath -Value "" -Encoding UTF8
        $traceSummary = Read-CodexExecTrace -TracePath $tracePath
        $selectedAttempt = [pscustomobject]@{
            schema = "codex-trace-attempt-v3"
            attempt_id = "$runId-$caseId-a0"
            attempt = 0
            status = $syntheticStatus
            failure_class = if ($DryRun) { "none" } else { "codex-unavailable" }
            message = ""
            exit_code = $null
            timed_out = $false
            timeout_seconds = $caseTimeoutSeconds
            duration_ms = 0
            process_id = 0
            child_tree_cleanup = "not-needed"
            trace = $tracePath
            stderr = $stderrPath
            final = $finalPath
            trace_summary = Get-SafeTraceSummary -TraceSummary $traceSummary
            artifacts = [ordered]@{
                trace = Get-FileEvidence -Path $tracePath
                stderr = Get-FileEvidence -Path $stderrPath
                final = Get-FileEvidence -Path $finalPath
            }
        }
    } else {
        $wrappedPrompt = @"
You are running a global Codex harness trace eval. Work read-only unless this
eval prompt explicitly asks for edits.

Codex home: $codexHomePath

Eval prompt:
$promptText
"@
        for ($attemptNumber = 1; $attemptNumber -le $caseMaxAttempts; $attemptNumber++) {
            $attemptDir = Join-Path $caseDir ("attempt-{0:D2}" -f $attemptNumber)
            New-Item -ItemType Directory -Force -Path $attemptDir | Out-Null
            $attempt = Invoke-CodexAttempt -Codex $codex -WorkingDirectory $codexHomePath -Prompt $wrappedPrompt `
                -AttemptId "$runId-$caseId-a$attemptNumber" -CaseId $caseId -AttemptNumber $attemptNumber `
                -TimeoutSeconds $caseTimeoutSeconds -TracePath (Join-Path $attemptDir "trace.jsonl") `
                -StderrPath (Join-Path $attemptDir "stderr.txt") -FinalPath (Join-Path $attemptDir "final.txt")
            $attemptRecords.Add($attempt) | Out-Null
            $selectedAttempt = $attempt
            if ($attempt.status -eq "completed") { break }
        }
    }

    $caseStopwatch.Stop()
    $executionAttempted = $attemptRecords.Count -gt 0
    $caseStatus = [string]$selectedAttempt.status
    $caseFailureClass = [string]$selectedAttempt.failure_class
    $caseRecord = [ordered]@{
        schema = "codex-trace-case-result-v3"
        run_id = $runId
        id = $sourceId
        case_directory = $caseId
        lane = $lane
        status = $caseStatus
        failure_class = $caseFailureClass
        message = [string]$selectedAttempt.message
        duration_ms = [int][Math]::Round($caseStopwatch.Elapsed.TotalMilliseconds)
        timeout_seconds = $caseTimeoutSeconds
        max_attempts = $caseMaxAttempts
        attempt_count = $attemptRecords.Count
        prompt_sha256 = $promptSha256
        expected_sha256 = $expectedSha256
        expectation_terms = [ordered]@{
            must_include = $mustInclude
            must_not_include = $mustNotInclude
            min_score = $minScore
        }
        event_tool_invariants = [ordered]@{
            must_include_events = $mustIncludeEvents
            must_not_include_events = $mustNotIncludeEvents
            must_include_tools = $mustIncludeTools
            must_not_include_tools = $mustNotIncludeTools
        }
        execution_attempted = $executionAttempted
        attempts = $attemptRecords.ToArray()
        trace = [string]$selectedAttempt.trace
        stderr = [string]$selectedAttempt.stderr
        final = [string]$selectedAttempt.final
        trace_summary = $selectedAttempt.trace_summary
        runner = $runner.name
        grader = $grader.name
        artifacts = $selectedAttempt.artifacts
        result_manifest = $caseResultPath
        manifests = [ordered]@{
            case_result = $caseResultPath
            run_result = $resultManifestPath
            case_grade = if ($NoGrade) { "" } else { $caseGradePath }
            run_grade = if ($NoGrade) { "" } else { $gradeManifestPath }
        }
    }
    $caseRecord | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $caseResultPath -Encoding UTF8
    $results.Add([pscustomobject]$caseRecord) | Out-Null
}

$executionFailures = @($results | Where-Object { $_.status -eq "failed" })
$completedCases = @($results | Where-Object { $_.status -eq "completed" })
$skippedCases = @($results | Where-Object { $_.status -in @("dry-run", "skipped-no-codex") })
$executionStatus = if ($executionFailures.Count -gt 0) { "failed" } elseif ($completedCases.Count -gt 0) { "passed" } else { "skipped" }

$manifest = [ordered]@{
    schema = "codex-global-trace-evals-v3"
    run_id = $runId
    status = if ($executionStatus -eq "failed") { "failed" } else { "success" }
    run_status = $executionStatus
    execution_status = $executionStatus
    grade_status = if ($NoGrade) { "not-requested" } else { "pending" }
    created_at = (Get-Date).ToString("o")
    codex_home = $codexHomePath
    run_dir = $runDir
    duration_ms = 0
    prompt_file = $PromptFile
    prompt_file_sha256 = $promptFileEvidence.sha256
    prompt_source = $promptFileEvidence
    dry_run = [bool]$DryRun
    include_disabled = [bool]$IncludeDisabled
    limit = $Limit
    runner = $runner
    grader = $grader
    environment = $environment
    counts = [ordered]@{
        total = $results.Count
        completed = $completedCases.Count
        failed = $executionFailures.Count
        skipped = $skippedCases.Count
    }
    failure_classes = @($executionFailures | Select-Object -ExpandProperty failure_class -Unique)
    manifests = [ordered]@{
        result = $resultManifestPath
        grade = if ($NoGrade) { "" } else { $gradeManifestPath }
    }
    results = $results.ToArray()
}
$manifest | ConvertTo-Json -Depth 18 | Set-Content -LiteralPath $resultManifestPath -Encoding UTF8

$gradeArtifacts = @()
$gradeStatus = if ($NoGrade) { "not-requested" } else { "failed" }
$graderFailureClass = "none"
if (-not $NoGrade) {
    if (-not (Test-Path -LiteralPath $gradeScript -PathType Leaf)) {
        $graderFailureClass = "grader-missing"
    } else {
        try {
            $gradeRaw = & $gradeScript -RunDir $runDir -AllowFailures
            $gradeJson = $gradeRaw | ConvertFrom-Json
            $gradeStatus = [string]$gradeJson.grade_status
            $gradeArtifacts = @($gradeJson.artifacts)
        } catch {
            $gradeStatus = "failed"
            $graderFailureClass = "grader-error"
        }
    }
}

$runStatus = if ($executionStatus -eq "failed" -or $gradeStatus -eq "failed") {
    "failed"
} elseif ($executionStatus -eq "passed" -and $gradeStatus -in @("passed", "not-requested")) {
    "passed"
} else {
    "skipped"
}
$topStatus = if ($runStatus -eq "failed") { "failed" } else { "success" }
$runStopwatch.Stop()

$manifest.status = $topStatus
$manifest.run_status = $runStatus
$manifest.grade_status = $gradeStatus
$manifest.duration_ms = [int][Math]::Round($runStopwatch.Elapsed.TotalMilliseconds)
$manifest.failure_classes = @(
    @($executionFailures | Select-Object -ExpandProperty failure_class -Unique) +
    $(if ($graderFailureClass -ne "none") { $graderFailureClass } else { @() }) +
    $(if ($gradeStatus -eq "failed" -and $graderFailureClass -eq "none") { "grade-failure" } else { @() })
) | Select-Object -Unique
$manifest | ConvertTo-Json -Depth 18 | Set-Content -LiteralPath $resultManifestPath -Encoding UTF8

if (Test-Path -LiteralPath $gradeManifestPath -PathType Leaf) {
    try {
        $gradeDocument = Get-Content -LiteralPath $gradeManifestPath -Raw | ConvertFrom-Json
        $gradeDocument.result_manifest = Get-FileEvidence -Path $resultManifestPath
        $gradeDocument | ConvertTo-Json -Depth 18 | Set-Content -LiteralPath $gradeManifestPath -Encoding UTF8
    } catch { }
}

$lines = if ($results.Count -gt 0) {
    ($results | ForEach-Object { "- $($_.status): $($_.id) failure=$($_.failure_class) attempts=$($_.attempt_count) duration_ms=$($_.duration_ms)" }) -join "`r`n"
} else {
    "- No trace eval cases ran."
}

$md = @"
# Codex Harness Trace Evals

- Run ID: $runId
- Status: $runStatus
- Created: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
- Duration ms: $($manifest.duration_ms)
- Dry run: $([bool]$DryRun)
- Prompt file: $PromptFile
- Prompt SHA-256: $($promptFileEvidence.sha256)
- Result manifest: $resultManifestPath
- Grade manifest: $(if ($NoGrade) { "Not requested." } else { $gradeManifestPath })
- Cases: $($results.Count)

## Results

$lines
"@
Set-Content -LiteralPath $summaryPath -Value $md -Encoding UTF8

$output = [ordered]@{
    status = $topStatus
    run_status = $runStatus
    summary = "Codex harness trace eval runner completed."
    run_id = $runId
    run_dir = $runDir
    duration_ms = $manifest.duration_ms
    dry_run = [bool]$DryRun
    prompt_file_sha256 = $promptFileEvidence.sha256
    counts = $manifest.counts
    failure_classes = $manifest.failure_classes
    results = $results.ToArray()
    manifests = [ordered]@{
        result = $resultManifestPath
        grade = if ($NoGrade) { "" } else { $gradeManifestPath }
    }
    artifacts = @($resultManifestPath, $summaryPath) + $gradeArtifacts
}

if ($runStatus -eq "failed" -and -not $AllowFailures) {
    throw "Trace eval run failed. See: $resultManifestPath"
}

$output | ConvertTo-Json -Depth 12 -Compress
