param(
    [string]$PromptFile = "",
    [switch]$DryRun,
    [switch]$IncludeDisabled,
    [int]$Limit = 0,
    [switch]$NoGrade,
    [switch]$AllowFailures,
    [string]$RunsRoot = ""
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
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
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

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
if (-not $PromptFile) {
    $PromptFile = Join-Path $root "evals\prompts.csv"
}
if (-not (Test-Path -LiteralPath $PromptFile -PathType Leaf)) {
    throw "Prompt file not found: $PromptFile"
}
$PromptFile = (Resolve-Path -LiteralPath $PromptFile).Path

if (-not $RunsRoot) {
    $RunsRoot = Join-Path $root "evals\runs"
}
New-Item -ItemType Directory -Force -Path $RunsRoot | Out-Null
$RunsRoot = (Resolve-Path -LiteralPath $RunsRoot).Path

$stamp = Get-Date -Format "yyyyMMdd-HHmmssfff"
$runDir = Join-Path $RunsRoot $stamp
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$resultManifestPath = Join-Path $runDir "evals.json"
$gradeManifestPath = Join-Path $runDir "grades.json"
$summaryPath = Join-Path $runDir "summary.md"
$gradeScript = Join-Path $PSScriptRoot "grade-codex-trace-evals.ps1"
$codex = Get-Command codex -ErrorAction SilentlyContinue

$runner = [ordered]@{
    name = "project-trace-runner"
    script = Get-FileEvidence -Path $PSCommandPath
    command = "codex exec --json"
    codex_available = [bool]$codex
    codex_command_path = if ($codex) { $codex.Source } else { "" }
}
$grader = [ordered]@{
    name = "project-trace-grader"
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
    $sourceId = [string]$case.id
    $caseId = ($sourceId -replace '[^A-Za-z0-9_.-]', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($caseId)) { $caseId = "case-$caseNumber" }
    $caseDir = Join-Path $runDir $caseId
    New-Item -ItemType Directory -Force -Path $caseDir | Out-Null

    $tracePath = Join-Path $caseDir "trace.jsonl"
    $stderrPath = Join-Path $caseDir "stderr.txt"
    $finalPath = Join-Path $caseDir "final.txt"
    $caseResultPath = Join-Path $caseDir "result.json"
    $caseGradePath = Join-Path $caseDir "grade.json"
    $promptText = [string]$case.prompt
    $expectedText = [string]$case.expected
    $lane = if ($case.PSObject.Properties.Name -contains "lane") { [string]$case.lane } else { [string]$case.kind }
    $mustInclude = @(Split-Terms -Value $case.must_include)
    $mustNotInclude = @(Split-Terms -Value $case.must_not_include)
    $minScore = 70
    $parsedMinScore = 0
    if ([int]::TryParse([string]$case.min_score, [ref]$parsedMinScore)) { $minScore = $parsedMinScore }
    $promptSha256 = Get-StringSha256 -Value $promptText
    $expectedSha256 = Get-StringSha256 -Value $expectedText

    $status = "completed"
    $message = ""
    $executionAttempted = $false

    if ($DryRun -or -not $codex) {
        $status = if ($codex) { "dry-run" } else { "skipped-no-codex" }
        $dryEvent = [ordered]@{
            schema = "codex-trace-event-v1"
            type = $status
            case_id = $sourceId
            prompt_sha256 = $promptSha256
            expected_sha256 = $expectedSha256
            execution_attempted = $false
        }
        $dryEvent | ConvertTo-Json -Depth 5 -Compress | Set-Content -LiteralPath $tracePath -Encoding UTF8
        Set-Content -LiteralPath $stderrPath -Value "" -Encoding UTF8
        $body = @"
Dry run for trace eval case: $sourceId

Prompt SHA-256: $promptSha256
Expected SHA-256: $expectedSha256
Required terms: $($mustInclude.Count)
Prohibited terms: $($mustNotInclude.Count)
"@
        Set-Content -LiteralPath $finalPath -Value $body -Encoding UTF8
    } else {
        $executionAttempted = $true
        $prompt = @"
You are evaluating the project harness. Work read-only unless the prompt explicitly asks for edits.

Project root: $root

Eval prompt:
$promptText
"@

        $output = $null
        try {
            $output = @(& $codex.Source exec --json --cd $root $prompt 2> $stderrPath)
            $output | Set-Content -LiteralPath $tracePath -Encoding UTF8
            if ($output.Count -gt 0) {
                $output | Select-Object -Last 1 | Set-Content -LiteralPath $finalPath -Encoding UTF8
            } else {
                Set-Content -LiteralPath $finalPath -Value "" -Encoding UTF8
            }
            if ($LASTEXITCODE -ne 0) {
                $status = "failed"
                $message = "codex exec exited with code $LASTEXITCODE"
            }
        } catch {
            $status = "failed"
            $message = $_.Exception.Message
            if ($null -ne $output) {
                $output | Set-Content -LiteralPath $tracePath -Encoding UTF8
            } elseif (-not (Test-Path -LiteralPath $tracePath)) {
                Set-Content -LiteralPath $tracePath -Value "" -Encoding UTF8
            }
            if (-not (Test-Path -LiteralPath $stderrPath)) {
                Set-Content -LiteralPath $stderrPath -Value "" -Encoding UTF8
            }
            Set-Content -LiteralPath $finalPath -Value $message -Encoding UTF8
        }
    }

    $artifactEvidence = [ordered]@{
        trace = Get-FileEvidence -Path $tracePath
        stderr = Get-FileEvidence -Path $stderrPath
        final = Get-FileEvidence -Path $finalPath
    }
    $caseRecord = [ordered]@{
        schema = "codex-trace-case-result-v2"
        id = $sourceId
        case_directory = $caseId
        lane = $lane
        status = $status
        message = $message
        prompt_sha256 = $promptSha256
        expected_sha256 = $expectedSha256
        expectation_terms = [ordered]@{
            must_include = $mustInclude
            must_not_include = $mustNotInclude
            min_score = $minScore
        }
        execution_attempted = $executionAttempted
        runner = $runner.name
        grader = $grader.name
        artifacts = $artifactEvidence
        manifests = [ordered]@{
            case_result = $caseResultPath
            run_result = $resultManifestPath
            case_grade = if ($NoGrade) { "" } else { $caseGradePath }
            run_grade = if ($NoGrade) { "" } else { $gradeManifestPath }
        }
    }
    $caseRecord | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $caseResultPath -Encoding UTF8

    $results.Add([pscustomobject]@{
        id = $sourceId
        lane = $lane
        kind = $lane
        status = $status
        message = $message
        trace = $tracePath
        stderr = $stderrPath
        final = $finalPath
        result_manifest = $caseResultPath
        prompt_sha256 = $promptSha256
        expected_sha256 = $expectedSha256
        min_score = $minScore
        expectation_terms = $caseRecord.expectation_terms
        execution_attempted = $executionAttempted
        runner = $runner.name
        grader = $grader.name
        artifacts = $artifactEvidence
    }) | Out-Null
}

$manifest = [ordered]@{
    schema = "codex-trace-evals-v2"
    created_at = (Get-Date).ToString("o")
    root = $root
    run_dir = $runDir
    prompt_file = $PromptFile
    prompt_file_sha256 = $promptFileEvidence.sha256
    prompt_source = $promptFileEvidence
    dry_run = [bool]$DryRun
    include_disabled = [bool]$IncludeDisabled
    limit = $Limit
    runner = $runner
    grader = $grader
    environment = $environment
    manifests = [ordered]@{
        result = $resultManifestPath
        grade = if ($NoGrade) { "" } else { $gradeManifestPath }
    }
    results = $results.ToArray()
}
$manifest | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $resultManifestPath -Encoding UTF8

$gradeArtifacts = @()
if (-not $NoGrade) {
    if (-not (Test-Path -LiteralPath $gradeScript -PathType Leaf)) {
        throw "Trace eval grader not found: $gradeScript"
    }
    $gradeRaw = & $gradeScript -RunDir $runDir -AllowFailures:$AllowFailures
    try {
        $gradeJson = $gradeRaw | ConvertFrom-Json
        $gradeArtifacts = @($gradeJson.artifacts)
    } catch {
        $gradeArtifacts = @()
    }
}

$lines = if ($results.Count -gt 0) {
    ($results | ForEach-Object { "- $($_.status): $($_.id) expected: $($_.expected)" }) -join "`r`n"
} else {
    "- No eval cases ran."
}

$md = @"
# Codex Trace Evals

- Created: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
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

[ordered]@{
    status = "success"
    summary = "Codex trace eval runner completed."
    dry_run = [bool]$DryRun
    prompt_file_sha256 = $promptFileEvidence.sha256
    manifests = [ordered]@{
        result = $resultManifestPath
        grade = if ($NoGrade) { "" } else { $gradeManifestPath }
    }
    artifacts = @($resultManifestPath, $summaryPath) + $gradeArtifacts
} | ConvertTo-Json -Depth 8 -Compress
