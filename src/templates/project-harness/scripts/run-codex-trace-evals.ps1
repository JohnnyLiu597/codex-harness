param(
    [string]$PromptFile = "",
    [switch]$DryRun,
    [switch]$IncludeDisabled,
    [int]$Limit = 0,
    [switch]$NoGrade,
    [switch]$AllowFailures
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
if (-not $PromptFile) {
    $PromptFile = Join-Path $root "evals\prompts.csv"
}
if (-not (Test-Path -LiteralPath $PromptFile)) {
    throw "Prompt file not found: $PromptFile"
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runDir = Join-Path $root ("evals\runs\" + $stamp)
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
    $caseDir = Join-Path $runDir $case.id
    New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
    $tracePath = Join-Path $caseDir "trace.jsonl"
    $stderrPath = Join-Path $caseDir "stderr.txt"
    $finalPath = Join-Path $caseDir "final.txt"

    if ($DryRun -or -not $codex) {
        Set-Content -LiteralPath $finalPath -Value "Dry run: $($case.prompt)" -Encoding UTF8
        $results.Add([pscustomobject]@{
            id = $case.id
            status = if ($codex) { "dry-run" } else { "skipped-no-codex" }
            trace = $tracePath
            final = $finalPath
            expected = $case.expected
            must_include = $case.must_include
            must_not_include = $case.must_not_include
            min_score = $case.min_score
        }) | Out-Null
        continue
    }

    $prompt = @"
You are evaluating the project harness. Work read-only unless the prompt explicitly asks for edits.

Project root: $root

Eval prompt:
$($case.prompt)
"@

    $status = "completed"
    $message = ""
    try {
        $output = & $codex.Source exec --json --cd $root $prompt 2> $stderrPath
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
        status = $status
        message = $message
        trace = $tracePath
        final = $finalPath
        expected = $case.expected
        must_include = $case.must_include
        must_not_include = $case.must_not_include
        min_score = $case.min_score
    }) | Out-Null
}

$summaryPath = Join-Path $runDir "summary.md"
$jsonPath = Join-Path $runDir "evals.json"
$record = [ordered]@{
    schema = "codex-trace-evals-v1"
    created_at = (Get-Date).ToString("o")
    root = $root
    prompt_file = $PromptFile
    dry_run = [bool]$DryRun
    results = $results.ToArray()
}
$record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$gradeArtifacts = @()
if (-not $NoGrade) {
    $gradeScript = Join-Path $PSScriptRoot "grade-codex-trace-evals.ps1"
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
- Cases: $($results.Count)

## Results

$lines
"@
Set-Content -LiteralPath $summaryPath -Value $md -Encoding UTF8

[ordered]@{
    status = "success"
    summary = "Codex trace eval runner completed."
    dry_run = [bool]$DryRun
    artifacts = @($jsonPath, $summaryPath) + $gradeArtifacts
} | ConvertTo-Json -Depth 5 -Compress
