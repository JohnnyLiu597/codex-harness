param(
    [string]$ProjectRoot = "",
    [string]$CodexHome = "$env:USERPROFILE\.codex",
    [string]$RunsRoot = "",
    [int]$Last = 10
)

$ErrorActionPreference = "Stop"

if (-not $ProjectRoot) {
    $scriptProjectRoot = Join-Path $PSScriptRoot ".."
    if ((Test-Path -LiteralPath (Join-Path $scriptProjectRoot "mission.md")) -and
        (Test-Path -LiteralPath (Join-Path $scriptProjectRoot "evals\prompts.csv"))) {
        $ProjectRoot = $scriptProjectRoot
    }
}

$isProject = -not [string]::IsNullOrWhiteSpace($ProjectRoot)
if ($isProject) {
    $root = (Resolve-Path -LiteralPath $ProjectRoot).Path
    if (-not $RunsRoot) { $RunsRoot = Join-Path $root "evals\runs" }
    $summaryRoot = Join-Path $root "artifacts\trace-eval-summaries"
} else {
    $root = (Resolve-Path -LiteralPath $CodexHome).Path
    if (-not $RunsRoot) { $RunsRoot = Join-Path $root "harness-evals\trace-evals\runs" }
    $summaryRoot = Join-Path $root "harness-evals\trace-evals\summaries"
}

if (-not (Test-Path -LiteralPath $RunsRoot)) {
    New-Item -ItemType Directory -Force -Path $RunsRoot | Out-Null
}
New-Item -ItemType Directory -Force -Path $summaryRoot | Out-Null

$runDirs = @(Get-ChildItem -LiteralPath $RunsRoot -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending)
if ($Last -gt 0) {
    $runDirs = @($runDirs | Select-Object -First $Last)
}

$runRecords = New-Object System.Collections.Generic.List[object]
$caseMap = @{}

foreach ($dir in $runDirs) {
    $evalPath = Join-Path $dir.FullName "evals.json"
    $gradePath = Join-Path $dir.FullName "grades.json"
    if (-not (Test-Path -LiteralPath $evalPath)) { continue }

    $evals = Get-Content -LiteralPath $evalPath -Raw | ConvertFrom-Json
    $grades = @()
    if (Test-Path -LiteralPath $gradePath) {
        $gradeDoc = Get-Content -LiteralPath $gradePath -Raw | ConvertFrom-Json
        $grades = @($gradeDoc.grades)
    }

    $passed = @($grades | Where-Object { $_.status -eq "passed" }).Count
    $failed = @($grades | Where-Object { $_.status -eq "failed" }).Count
    $skipped = @($grades | Where-Object { $_.status -eq "skipped" }).Count
    $scores = @($grades | Where-Object { $null -ne $_.score } | ForEach-Object { [double]$_.score })
    $averageScore = if ($scores.Count -gt 0) { [Math]::Round((($scores | Measure-Object -Average).Average), 2) } else { $null }

    foreach ($grade in $grades) {
        $id = [string]$grade.id
        if (-not $caseMap.ContainsKey($id)) {
            $caseMap[$id] = New-Object System.Collections.Generic.List[object]
        }
        $caseMap[$id].Add([pscustomobject]@{
            run = $dir.Name
            status = $grade.status
            run_status = $grade.run_status
            score = $grade.score
            missing = @($grade.missing)
            prohibited = @($grade.prohibited)
        }) | Out-Null
    }

    $runRecords.Add([pscustomobject]@{
        run = $dir.Name
        path = $dir.FullName
        dry_run = [bool]$evals.dry_run
        cases = @($evals.results).Count
        grades = @($grades).Count
        passed = $passed
        failed = $failed
        skipped = $skipped
        average_score = $averageScore
    }) | Out-Null
}

$caseSummaries = New-Object System.Collections.Generic.List[object]
foreach ($key in @($caseMap.Keys | Sort-Object)) {
    $id = [string]$key
    $historyItems = New-Object System.Collections.Generic.List[object]
    foreach ($item in $caseMap[$key]) {
        $historyItems.Add($item) | Out-Null
    }
    $history = @($historyItems.ToArray())
    $latest = @($history | Select-Object -First 1)[0]
    $failCount = @($history | Where-Object { $_.status -eq "failed" }).Count
    $prohibitedCount = @($history | Where-Object { @($_.prohibited).Count -gt 0 }).Count
    $caseSummaries.Add([pscustomobject]@{
        id = $id
        latest_status = $latest.status
        latest_score = $latest.score
        runs_seen = $history.Count
        failures = $failCount
        prohibited_violations = $prohibitedCount
        recommended_destination = if ($failCount -ge 2) { "learning-intake-or-skill" } elseif ($prohibitedCount -gt 0) { "rule-or-tool-eval" } else { "watch" }
        history = $history
    }) | Out-Null
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$summaryDir = Join-Path $summaryRoot $stamp
New-Item -ItemType Directory -Force -Path $summaryDir | Out-Null
$jsonPath = Join-Path $summaryDir "trace-summary.json"
$mdPath = Join-Path $summaryDir "summary.md"
$indexPath = Join-Path $RunsRoot "index.json"

$status = if (@($caseSummaries | Where-Object { $_.latest_status -eq "failed" }).Count -gt 0) { "warning" } else { "passed" }
$record = [ordered]@{
    schema = "codex-trace-eval-summary-v1"
    status = $status
    created_at = (Get-Date).ToString("o")
    root = $root
    runs_root = (Resolve-Path -LiteralPath $RunsRoot).Path
    runs_analyzed = $runRecords.Count
    case_count = $caseSummaries.Count
    runs = $runRecords.ToArray()
    cases = $caseSummaries.ToArray()
}

$record | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$record | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $indexPath -Encoding UTF8

$runLines = if ($runRecords.Count -gt 0) {
    ($runRecords | ForEach-Object { "- $($_.run): cases=$($_.cases) passed=$($_.passed) failed=$($_.failed) skipped=$($_.skipped) avg=$($_.average_score)" }) -join "`r`n"
} else {
    "- No trace eval runs found."
}
$caseLines = if ($caseSummaries.Count -gt 0) {
    ($caseSummaries | ForEach-Object { "- $($_.latest_status): $($_.id) latest_score=$($_.latest_score) failures=$($_.failures) destination=$($_.recommended_destination)" }) -join "`r`n"
} else {
    "- No cases summarized."
}

$md = @"
# Trace Eval Summary

- Status: $status
- Created: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
- Runs analyzed: $($runRecords.Count)
- Cases summarized: $($caseSummaries.Count)

## Runs

$runLines

## Cases

$caseLines
"@
Set-Content -LiteralPath $mdPath -Value $md -Encoding UTF8

[ordered]@{
    status = if ($status -eq "passed") { "success" } else { "warning" }
    summary = "Trace eval summary created."
    artifacts = @($jsonPath, $mdPath, $indexPath)
} | ConvertTo-Json -Depth 6 -Compress
