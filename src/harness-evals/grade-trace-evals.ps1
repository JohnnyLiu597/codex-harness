param(
    [Parameter(Mandatory = $true)][string]$RunDir,
    [switch]$AllowFailures
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
                $finalAssistantMessage = [string](Get-ObjectPropertyValue -Object $item -Names @("text", "message", "content") -Default "")
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

function Compare-ExactInvariants {
    param(
        [object[]]$Observed,
        [object[]]$Required,
        [object[]]$Prohibited
    )

    $observedSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($value in @($Observed)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$value)) { $observedSet.Add(([string]$value).Trim()) | Out-Null }
    }

    $found = New-Object System.Collections.Generic.List[string]
    $missing = New-Object System.Collections.Generic.List[string]
    $violations = New-Object System.Collections.Generic.List[string]
    foreach ($value in @($Required)) {
        $term = ([string]$value).Trim()
        if ($observedSet.Contains($term)) { $found.Add($term) | Out-Null } else { $missing.Add($term) | Out-Null }
    }
    foreach ($value in @($Prohibited)) {
        $term = ([string]$value).Trim()
        if ($observedSet.Contains($term)) { $violations.Add($term) | Out-Null }
    }

    return [pscustomobject]@{
        status = if ($missing.Count -eq 0 -and $violations.Count -eq 0) { "passed" } else { "failed" }
        observed = @($Observed)
        found = $found.ToArray()
        missing = $missing.ToArray()
        prohibited = $violations.ToArray()
    }
}

function Get-EnvironmentEvidence {
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
        proxy_variables_present = [bool]($proxyCount -gt 0)
        proxy_variable_count = $proxyCount
        auth_like_variables_present = [bool]($authCount -gt 0)
        auth_like_variable_count = $authCount
        environment_values_recorded = $false
    }
}

$gradeStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$resolvedRunDir = (Resolve-Path -LiteralPath $RunDir).Path
$evalPath = Join-Path $resolvedRunDir "evals.json"
if (-not (Test-Path -LiteralPath $evalPath -PathType Leaf)) {
    throw "evals.json not found: $evalPath"
}

$evals = Get-Content -LiteralPath $evalPath -Raw | ConvertFrom-Json
$grades = New-Object System.Collections.Generic.List[object]
$caseGradeArtifacts = New-Object System.Collections.Generic.List[string]
$grader = [ordered]@{
    name = "global-trace-grader"
    version = "3.0"
    script = Get-FileEvidence -Path $PSCommandPath
    allow_failures = [bool]$AllowFailures
    algorithm = "final assistant keyword smoke plus exact event and tool invariants"
    keyword_grading = [ordered]@{
        label = "smoke"
        version = "keyword-smoke-v3"
        scope = "final-assistant-message"
        case_sensitive = $false
        raw_prompt_or_trace_text_used = $false
    }
}

foreach ($result in @($evals.results)) {
    $caseStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $structuredTerms = Get-ObjectPropertyValue -Object $result -Names @("expectation_terms") -Default $null
    $mustInclude = if ($null -ne $structuredTerms) {
        @(Split-Terms -Value $structuredTerms.must_include)
    } else {
        @(Split-Terms -Value $result.must_include)
    }
    $mustNotInclude = if ($null -ne $structuredTerms) {
        @(Split-Terms -Value $structuredTerms.must_not_include)
    } else {
        @(Split-Terms -Value $result.must_not_include)
    }

    $minScore = 70
    $minScoreValue = if ($null -ne $structuredTerms) { $structuredTerms.min_score } else { $result.min_score }
    $parsedMinScore = 0
    if ([int]::TryParse([string]$minScoreValue, [ref]$parsedMinScore)) { $minScore = [Math]::Max(0, [Math]::Min(100, $parsedMinScore)) }
    $promptSha256 = if ($result.PSObject.Properties.Name -contains "prompt_sha256") { [string]$result.prompt_sha256 } else { "" }
    $expectedSha256 = if ($result.PSObject.Properties.Name -contains "expected_sha256") { [string]$result.expected_sha256 } else { "" }

    $structuredInvariants = Get-ObjectPropertyValue -Object $result -Names @("event_tool_invariants") -Default $null
    $mustIncludeEvents = @(Split-Terms -Value (Get-ObjectPropertyValue -Object $structuredInvariants -Names @("must_include_events") -Default ""))
    $mustNotIncludeEvents = @(Split-Terms -Value (Get-ObjectPropertyValue -Object $structuredInvariants -Names @("must_not_include_events") -Default ""))
    $mustIncludeTools = @(Split-Terms -Value (Get-ObjectPropertyValue -Object $structuredInvariants -Names @("must_include_tools") -Default ""))
    $mustNotIncludeTools = @(Split-Terms -Value (Get-ObjectPropertyValue -Object $structuredInvariants -Names @("must_not_include_tools") -Default ""))

    $traceSummary = Read-CodexExecTrace -TracePath ([string]$result.trace)
    $finalText = [string]$traceSummary.final_assistant_message
    $found = New-Object System.Collections.Generic.List[string]
    $missing = New-Object System.Collections.Generic.List[string]
    $prohibited = New-Object System.Collections.Generic.List[string]
    $score = $null
    $keywordStatus = "skipped"
    $eventGrade = Compare-ExactInvariants -Observed @($traceSummary.event_types) -Required $mustIncludeEvents -Prohibited $mustNotIncludeEvents
    $toolGrade = Compare-ExactInvariants -Observed @($traceSummary.tool_names) -Required $mustIncludeTools -Prohibited $mustNotIncludeTools
    $gradeStatus = "skipped"
    $failureClass = "none"

    if ($result.status -eq "completed") {
        foreach ($term in $mustInclude) {
            if ($finalText.IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $found.Add($term) | Out-Null
            } else {
                $missing.Add($term) | Out-Null
            }
        }
        foreach ($term in $mustNotInclude) {
            if ($finalText.IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $prohibited.Add($term) | Out-Null
            }
        }

        $score = if ($mustInclude.Count -gt 0) {
            [int][Math]::Round(100 * ($found.Count / $mustInclude.Count))
        } else {
            100
        }
        $keywordStatus = if ($traceSummary.assistant_message_count -gt 0 -and $score -ge $minScore -and $prohibited.Count -eq 0) { "passed" } else { "failed" }

        if ($traceSummary.assistant_message_count -eq 0) {
            $failureClass = "missing-final-assistant"
        } elseif ($keywordStatus -eq "failed") {
            $failureClass = "keyword-smoke"
        } elseif ($eventGrade.status -eq "failed") {
            $failureClass = "event-invariant"
        } elseif ($toolGrade.status -eq "failed") {
            $failureClass = "tool-invariant"
        }
        $gradeStatus = if ($failureClass -eq "none") { "passed" } else { "failed" }
    } elseif ($result.status -eq "failed") {
        $gradeStatus = "failed"
        $failureClass = [string](Get-ObjectPropertyValue -Object $result -Names @("failure_class") -Default "execution-failure")
    }

    $caseStopwatch.Stop()
    $caseDir = if ($result.result_manifest) { Split-Path -Parent ([string]$result.result_manifest) } elseif ($result.final) { Split-Path -Parent ([string]$result.final) } else { $resolvedRunDir }
    $caseGradePath = Join-Path $caseDir "grade.json"
    $gradeRecord = [ordered]@{
        schema = "codex-trace-case-grade-v3"
        run_id = [string](Get-ObjectPropertyValue -Object $evals -Names @("run_id") -Default "")
        id = $result.id
        lane = $result.lane
        status = $gradeStatus
        failure_class = $failureClass
        run_status = $result.status
        duration_ms = [int][Math]::Round($caseStopwatch.Elapsed.TotalMilliseconds)
        score = $score
        min_score = $minScore
        prompt_sha256 = $promptSha256
        expected_sha256 = $expectedSha256
        grading = [ordered]@{
            keyword_smoke = [ordered]@{
                label = "smoke"
                version = "keyword-smoke-v3"
                scope = "final-assistant-message"
                status = $keywordStatus
                found = $found.ToArray()
                missing = $missing.ToArray()
                prohibited = $prohibited.ToArray()
            }
            events = [ordered]@{
                status = $eventGrade.status
                required = $mustIncludeEvents
                prohibited_terms = $mustNotIncludeEvents
                observed = $eventGrade.observed
                found = $eventGrade.found
                missing = $eventGrade.missing
                prohibited = $eventGrade.prohibited
            }
            tools = [ordered]@{
                status = $toolGrade.status
                required = $mustIncludeTools
                prohibited_terms = $mustNotIncludeTools
                observed = $toolGrade.observed
                found = $toolGrade.found
                missing = $toolGrade.missing
                prohibited = $toolGrade.prohibited
            }
        }
        found = $found.ToArray()
        missing = $missing.ToArray()
        prohibited = $prohibited.ToArray()
        final_assistant = [ordered]@{
            sha256 = $traceSummary.final_assistant_sha256
            bytes = $traceSummary.final_assistant_bytes
            message_count = $traceSummary.assistant_message_count
            raw_text_recorded = $false
        }
        trace_parse = [ordered]@{
            json_line_count = $traceSummary.json_line_count
            invalid_json_line_count = $traceSummary.invalid_json_line_count
            ignored_process_cleanup_line_count = $traceSummary.ignored_process_cleanup_line_count
            error_event_count = $traceSummary.error_event_count
        }
        runner = if ($result.PSObject.Properties.Name -contains "runner") { $result.runner } else { $evals.runner.name }
        grader = $grader.name
        artifacts = [ordered]@{
            trace = Get-FileEvidence -Path ([string]$result.trace)
            final = Get-FileEvidence -Path ([string]$result.final)
            case_result = Get-FileEvidence -Path ([string]$result.result_manifest)
        }
        manifests = [ordered]@{
            run_result = $evalPath
            case_grade = $caseGradePath
            run_grade = (Join-Path $resolvedRunDir "grades.json")
        }
    }
    $gradeRecord | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $caseGradePath -Encoding UTF8
    $caseGradeArtifacts.Add($caseGradePath) | Out-Null

    $grades.Add([pscustomobject]@{
        id = $result.id
        lane = $result.lane
        status = $gradeStatus
        failure_class = $failureClass
        run_status = $result.status
        duration_ms = $gradeRecord.duration_ms
        score = $score
        min_score = $minScore
        found = $found.ToArray()
        missing = $missing.ToArray()
        prohibited = $prohibited.ToArray()
        prompt_sha256 = $promptSha256
        expected_sha256 = $expectedSha256
        grading = $gradeRecord.grading
        final_assistant = $gradeRecord.final_assistant
        trace_parse = $gradeRecord.trace_parse
        runner = $gradeRecord.runner
        grader = $grader.name
        trace = $result.trace
        final = $result.final
        result_manifest = $result.result_manifest
        grade_manifest = $caseGradePath
        artifacts = $gradeRecord.artifacts
    }) | Out-Null
}

$failed = @($grades | Where-Object { $_.status -eq "failed" })
$completed = @($grades | Where-Object { $_.run_status -eq "completed" })
$status = if ($failed.Count -gt 0) { "failed" } elseif ($completed.Count -eq 0) { "skipped" } else { "passed" }
$gradeStopwatch.Stop()

$gradesPath = Join-Path $resolvedRunDir "grades.json"
$summaryPath = Join-Path $resolvedRunDir "grades.md"
$promptSource = if ($evals.PSObject.Properties.Name -contains "prompt_source") {
    $evals.prompt_source
} else {
    Get-FileEvidence -Path ([string]$evals.prompt_file)
}

$gradeManifest = [ordered]@{
    schema = "codex-global-trace-grades-v3"
    run_id = [string](Get-ObjectPropertyValue -Object $evals -Names @("run_id") -Default "")
    status = $status
    created_at = (Get-Date).ToString("o")
    duration_ms = [int][Math]::Round($gradeStopwatch.Elapsed.TotalMilliseconds)
    run_dir = $resolvedRunDir
    result_manifest = Get-FileEvidence -Path $evalPath
    grade_manifest = $gradesPath
    prompt_source = $promptSource
    runner = $evals.runner
    grader = $grader
    environment = Get-EnvironmentEvidence
    counts = [ordered]@{
        total = $grades.Count
        completed = $completed.Count
        failed = $failed.Count
        skipped = @($grades | Where-Object { $_.status -eq "skipped" }).Count
    }
    failure_classes = @($failed | Select-Object -ExpandProperty failure_class -Unique)
    grades = $grades.ToArray()
}
$gradeManifest | ConvertTo-Json -Depth 18 | Set-Content -LiteralPath $gradesPath -Encoding UTF8

$gradeLines = if ($grades.Count -gt 0) {
    ($grades | ForEach-Object {
        $scoreText = if ($null -eq $_.score) { "not-run" } else { [string]$_.score }
        "- $($_.status): $($_.id) class=$($_.failure_class) score=$scoreText min=$($_.min_score) missing=$($_.missing -join '|') prohibited=$($_.prohibited -join '|')"
    }) -join "`r`n"
} else {
    "- No grades."
}

$md = @"
# Codex Harness Trace Grades

- Status: $status
- Duration ms: $($gradeManifest.duration_ms)
- Result manifest: $evalPath
- Grade manifest: $gradesPath
- Completed cases: $($completed.Count)
- Failed cases: $($failed.Count)
- Keyword grader: smoke / keyword-smoke-v3 / final-assistant-message

## Grades

$gradeLines
"@
Set-Content -LiteralPath $summaryPath -Value $md -Encoding UTF8

if ($failed.Count -gt 0 -and -not $AllowFailures) {
    throw "Trace eval grading failed: $($failed.id -join ', ')"
}

[ordered]@{
    status = if ($status -eq "failed") { "failed" } else { "success" }
    summary = "Codex harness trace eval grading completed."
    run_id = $gradeManifest.run_id
    grade_status = $status
    duration_ms = $gradeManifest.duration_ms
    failure_classes = $gradeManifest.failure_classes
    manifests = [ordered]@{
        result = $evalPath
        grade = $gradesPath
    }
    artifacts = @($gradesPath, $summaryPath) + $caseGradeArtifacts.ToArray()
} | ConvertTo-Json -Depth 10 -Compress
