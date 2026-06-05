param(
    [string]$CodexHome = "$env:USERPROFILE\.codex",
    [string]$PromptFile = "",
    [switch]$DryRun,
    [switch]$IncludeDisabled,
    [int]$Limit = 0,
    [switch]$NoGrade,
    [switch]$AllowFailures
)

$ErrorActionPreference = "Stop"

$codexHomePath = (Resolve-Path -LiteralPath $CodexHome).Path
if (-not $PromptFile) {
    $PromptFile = Join-Path $codexHomePath "harness-evals\trace-evals\prompts.csv"
}
if (-not (Test-Path -LiteralPath $PromptFile)) {
    throw "Prompt file not found: $PromptFile"
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runDir = Join-Path $codexHomePath ("harness-evals\trace-evals\runs\" + $stamp)
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$codex = Get-Command codex -ErrorAction SilentlyContinue
$cases = @(Import-Csv -LiteralPath $PromptFile)
if (-not $IncludeDisabled) {
    $cases = @($cases | Where-Object { $_.enabled -eq "true" })
}
if ($Limit -gt 0) {
    $cases = @($cases | Select-Object -First $Limit)
}

$results = New-Object System.Collections.Generic.List[object]

foreach ($case in $cases) {
    $caseId = ($case.id -replace '[^A-Za-z0-9_.-]', '-')
    $caseDir = Join-Path $runDir $caseId
    New-Item -ItemType Directory -Force -Path $caseDir | Out-Null

    $tracePath = Join-Path $caseDir "trace.jsonl"
    $stderrPath = Join-Path $caseDir "stderr.txt"
    $finalPath = Join-Path $caseDir "final.txt"

    if ($DryRun -or -not $codex) {
        $status = if ($codex) { "dry-run" } else { "skipped-no-codex" }
        $body = @"
Dry run for trace eval case: $($case.id)

Prompt:
$($case.prompt)

Expected:
$($case.expected)
"@
        Set-Content -LiteralPath $finalPath -Value $body -Encoding UTF8
        $results.Add([pscustomobject]@{
            id = $case.id
            lane = $case.lane
            status = $status
            message = ""
            trace = $tracePath
            stderr = $stderrPath
            final = $finalPath
            expected = $case.expected
            must_include = $case.must_include
            must_not_include = $case.must_not_include
            min_score = $case.min_score
        }) | Out-Null
        continue
    }

    $prompt = @"
You are running a global Codex harness trace eval. Work read-only unless this
eval prompt explicitly asks for edits.

Codex home: $codexHomePath

Eval prompt:
$($case.prompt)
"@

    $status = "completed"
    $message = ""
    $output = $null
    try {
        $output = & $codex.Source exec --json --cd $codexHomePath $prompt 2> $stderrPath
        $output | Set-Content -LiteralPath $tracePath -Encoding UTF8
        $output | Select-Object -Last 1 | Set-Content -LiteralPath $finalPath -Encoding UTF8
        if ($LASTEXITCODE -ne 0) {
            $status = "failed"
            $message = "codex exec exited with code $LASTEXITCODE"
        }
    } catch {
        $status = "failed"
        $message = $_.Exception.Message
        if ($null -ne $output) {
            $output | Set-Content -LiteralPath $tracePath -Encoding UTF8
        }
        Set-Content -LiteralPath $finalPath -Value $message -Encoding UTF8
    }

    $results.Add([pscustomobject]@{
        id = $case.id
        lane = $case.lane
        status = $status
        message = $message
        trace = $tracePath
        stderr = $stderrPath
        final = $finalPath
        expected = $case.expected
        must_include = $case.must_include
        must_not_include = $case.must_not_include
        min_score = $case.min_score
    }) | Out-Null
}

$jsonPath = Join-Path $runDir "evals.json"
$summaryPath = Join-Path $runDir "summary.md"

[ordered]@{
    schema = "codex-global-trace-evals-v1"
    created_at = (Get-Date).ToString("o")
    codex_home = $codexHomePath
    prompt_file = $PromptFile
    dry_run = [bool]$DryRun
    results = $results.ToArray()
} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$gradeArtifacts = @()
if (-not $NoGrade) {
    $gradeScript = Join-Path $codexHomePath "harness-evals\grade-trace-evals.ps1"
    $gradeRaw = & $gradeScript -RunDir $runDir -AllowFailures:$AllowFailures
    try {
        $gradeJson = $gradeRaw | ConvertFrom-Json
        $gradeArtifacts = @($gradeJson.artifacts)
    } catch {
        $gradeArtifacts = @()
    }
}

$lines = if ($results.Count -gt 0) {
    ($results | ForEach-Object { "- $($_.status): $($_.id) $($_.expected)" }) -join "`r`n"
} else {
    "- No trace eval cases ran."
}

$md = @"
# Codex Harness Trace Evals

- Created: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
- Dry run: $([bool]$DryRun)
- Prompt file: $PromptFile
- Cases: $($results.Count)

## Results

$lines
"@
Set-Content -LiteralPath $summaryPath -Value $md -Encoding UTF8

[ordered]@{
    status = "success"
    summary = "Codex harness trace eval runner completed."
    dry_run = [bool]$DryRun
    artifacts = @($jsonPath, $summaryPath) + $gradeArtifacts
} | ConvertTo-Json -Depth 6 -Compress
