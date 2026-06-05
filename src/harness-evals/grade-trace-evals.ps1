param(
    [Parameter(Mandatory = $true)][string]$RunDir,
    [switch]$AllowFailures
)

$ErrorActionPreference = "Stop"

$resolvedRunDir = (Resolve-Path -LiteralPath $RunDir).Path
$evalPath = Join-Path $resolvedRunDir "evals.json"
if (-not (Test-Path -LiteralPath $evalPath)) {
    throw "evals.json not found: $evalPath"
}

$evals = Get-Content -LiteralPath $evalPath -Raw | ConvertFrom-Json
$grades = New-Object System.Collections.Generic.List[object]

function Split-Terms {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }
    return @($Value -split "\|" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Read-TraceText {
    param([string]$TracePath, [string]$FinalPath)
    $parts = New-Object System.Collections.Generic.List[string]
    if ($FinalPath -and (Test-Path -LiteralPath $FinalPath)) {
        $parts.Add((Get-Content -LiteralPath $FinalPath -Raw)) | Out-Null
    }
    if ($TracePath -and (Test-Path -LiteralPath $TracePath)) {
        foreach ($line in Get-Content -LiteralPath $TracePath -ErrorAction SilentlyContinue) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts.Add($line) | Out-Null
            try {
                $obj = $line | ConvertFrom-Json
                $parts.Add(($obj | ConvertTo-Json -Depth 20 -Compress)) | Out-Null
            } catch {
                # Keep raw line only.
            }
        }
    }
    return ($parts -join "`n")
}

foreach ($result in $evals.results) {
    if ($result.status -ne "completed" -and $result.status -ne "failed") {
        $grades.Add([pscustomobject]@{
            id = $result.id
            lane = $result.lane
            status = "skipped"
            run_status = $result.status
            score = $null
            min_score = if ($result.min_score) { [int]$result.min_score } else { 70 }
            found = @()
            missing = @()
            prohibited = @()
            expected = $result.expected
        }) | Out-Null
        continue
    }

    $mustInclude = @(Split-Terms -Value $result.must_include)
    $mustNotInclude = @(Split-Terms -Value $result.must_not_include)
    $minScore = 70
    if ($result.min_score) {
        $minScore = [int]$result.min_score
    }

    $text = Read-TraceText -TracePath $result.trace -FinalPath $result.final
    $found = @()
    $missing = @()
    foreach ($term in $mustInclude) {
        if ($text.IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $found += $term
        } else {
            $missing += $term
        }
    }

    $prohibited = @()
    foreach ($term in $mustNotInclude) {
        if ($text.IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $prohibited += $term
        }
    }

    $score = if ($mustInclude.Count -gt 0) {
        [int][Math]::Round(100 * ($found.Count / $mustInclude.Count))
    } else {
        100
    }

    $gradeStatus = "skipped"
    if ($result.status -eq "completed") {
        $gradeStatus = if ($score -ge $minScore -and $prohibited.Count -eq 0) { "passed" } else { "failed" }
    } elseif ($result.status -eq "failed") {
        $gradeStatus = "failed"
    }

    $grades.Add([pscustomobject]@{
        id = $result.id
        lane = $result.lane
        status = $gradeStatus
        run_status = $result.status
        score = $score
        min_score = $minScore
        found = $found
        missing = $missing
        prohibited = $prohibited
        expected = $result.expected
    }) | Out-Null
}

$failed = @($grades | Where-Object { $_.status -eq "failed" })
$completed = @($grades | Where-Object { $_.run_status -eq "completed" })
$status = if ($failed.Count -gt 0) { "failed" } elseif ($completed.Count -eq 0) { "skipped" } else { "passed" }

$gradesPath = Join-Path $resolvedRunDir "grades.json"
$summaryPath = Join-Path $resolvedRunDir "grades.md"

[ordered]@{
    schema = "codex-global-trace-grades-v1"
    status = $status
    created_at = (Get-Date).ToString("o")
    run_dir = $resolvedRunDir
    grades = $grades.ToArray()
} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $gradesPath -Encoding UTF8

$gradeLines = if ($grades.Count -gt 0) {
    ($grades | ForEach-Object {
        $scoreText = if ($null -eq $_.score) { "not-run" } else { [string]$_.score }
        "- $($_.status): $($_.id) score=$scoreText min=$($_.min_score) missing=$($_.missing -join '|') prohibited=$($_.prohibited -join '|')"
    }) -join "`r`n"
} else {
    "- No grades."
}

$md = @"
# Codex Harness Trace Grades

- Status: $status
- Completed cases: $($completed.Count)
- Failed cases: $($failed.Count)

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
    grade_status = $status
    artifacts = @($gradesPath, $summaryPath)
} | ConvertTo-Json -Depth 6 -Compress
