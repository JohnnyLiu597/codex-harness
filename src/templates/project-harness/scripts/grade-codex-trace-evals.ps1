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

function Read-TraceText {
    param([string]$TracePath, [string]$FinalPath)

    $parts = New-Object System.Collections.Generic.List[string]
    if ($FinalPath -and (Test-Path -LiteralPath $FinalPath -PathType Leaf)) {
        $parts.Add((Get-Content -LiteralPath $FinalPath -Raw)) | Out-Null
    }
    if ($TracePath -and (Test-Path -LiteralPath $TracePath -PathType Leaf)) {
        foreach ($line in Get-Content -LiteralPath $TracePath -ErrorAction SilentlyContinue) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts.Add($line) | Out-Null
            try {
                $obj = $line | ConvertFrom-Json
                $parts.Add(($obj | ConvertTo-Json -Depth 20 -Compress)) | Out-Null
            } catch {
                # Raw trace text remains available for deterministic term checks.
            }
        }
    }
    return ($parts -join "`n")
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

$resolvedRunDir = (Resolve-Path -LiteralPath $RunDir).Path
$evalPath = Join-Path $resolvedRunDir "evals.json"
if (-not (Test-Path -LiteralPath $evalPath -PathType Leaf)) {
    throw "evals.json not found: $evalPath"
}

$evals = Get-Content -LiteralPath $evalPath -Raw | ConvertFrom-Json
$grades = New-Object System.Collections.Generic.List[object]
$caseGradeArtifacts = New-Object System.Collections.Generic.List[string]
$grader = [ordered]@{
    name = "project-trace-grader"
    script = Get-FileEvidence -Path $PSCommandPath
    allow_failures = [bool]$AllowFailures
    algorithm = "case-insensitive required and prohibited term matching"
}

foreach ($result in @($evals.results)) {
    $structuredTerms = $null
    if ($result.PSObject.Properties.Name -contains "expectation_terms") {
        $structuredTerms = $result.expectation_terms
    }
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
    if ([int]::TryParse([string]$minScoreValue, [ref]$parsedMinScore)) { $minScore = $parsedMinScore }
    $promptSha256 = if ($result.PSObject.Properties.Name -contains "prompt_sha256") {
        [string]$result.prompt_sha256
    } elseif ($result.PSObject.Properties.Name -contains "prompt") {
        Get-StringSha256 -Value ([string]$result.prompt)
    } else { "" }
    $expectedSha256 = if ($result.PSObject.Properties.Name -contains "expected_sha256") {
        [string]$result.expected_sha256
    } elseif ($result.PSObject.Properties.Name -contains "expected") {
        Get-StringSha256 -Value ([string]$result.expected)
    } else { "" }

    $found = @()
    $missing = @()
    $prohibited = @()
    $score = $null
    $gradeStatus = "skipped"

    if ($result.status -eq "completed" -or $result.status -eq "failed") {
        $text = Read-TraceText -TracePath $result.trace -FinalPath $result.final
        foreach ($term in $mustInclude) {
            if ($text.IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $found += $term
            } else {
                $missing += $term
            }
        }
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
        if ($result.status -eq "completed") {
            $gradeStatus = if ($score -ge $minScore -and $prohibited.Count -eq 0) { "passed" } else { "failed" }
        } else {
            $gradeStatus = "failed"
        }
    }

    $caseDir = if ($result.final) { Split-Path -Parent ([string]$result.final) } else { $resolvedRunDir }
    $caseGradePath = Join-Path $caseDir "grade.json"
    $gradeRecord = [ordered]@{
        schema = "codex-trace-case-grade-v2"
        id = $result.id
        lane = if ($result.PSObject.Properties.Name -contains "lane") { $result.lane } else { $result.kind }
        status = $gradeStatus
        run_status = $result.status
        score = $score
        min_score = $minScore
        prompt_sha256 = $promptSha256
        expected_sha256 = $expectedSha256
        expectation_terms = [ordered]@{
            must_include = $mustInclude
            must_not_include = $mustNotInclude
            found = $found
            missing = $missing
            prohibited = $prohibited
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
    $gradeRecord | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $caseGradePath -Encoding UTF8
    $caseGradeArtifacts.Add($caseGradePath) | Out-Null

    $grades.Add([pscustomobject]@{
        id = $result.id
        lane = $gradeRecord.lane
        kind = $gradeRecord.lane
        status = $gradeStatus
        run_status = $result.status
        score = $score
        min_score = $minScore
        found = $found
        missing = $missing
        prohibited = $prohibited
        prompt_sha256 = $gradeRecord.prompt_sha256
        expected_sha256 = $gradeRecord.expected_sha256
        expectation_terms = $gradeRecord.expectation_terms
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

$gradesPath = Join-Path $resolvedRunDir "grades.json"
$summaryPath = Join-Path $resolvedRunDir "grades.md"
$promptSource = if ($evals.PSObject.Properties.Name -contains "prompt_source") {
    $evals.prompt_source
} else {
    Get-FileEvidence -Path ([string]$evals.prompt_file)
}

$gradeManifest = [ordered]@{
    schema = "codex-trace-grades-v2"
    status = $status
    created_at = (Get-Date).ToString("o")
    run_dir = $resolvedRunDir
    result_manifest = Get-FileEvidence -Path $evalPath
    grade_manifest = $gradesPath
    prompt_source = $promptSource
    runner = $evals.runner
    grader = $grader
    environment = Get-EnvironmentEvidence
    grades = $grades.ToArray()
}
$gradeManifest | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $gradesPath -Encoding UTF8

$gradeLines = if ($grades.Count -gt 0) {
    ($grades | ForEach-Object {
        $scoreText = if ($null -eq $_.score) { "not-run" } else { [string]$_.score }
        "- $($_.status): $($_.id) score=$scoreText min=$($_.min_score) missing=$($_.missing -join '|') prohibited=$($_.prohibited -join '|')"
    }) -join "`r`n"
} else {
    "- No grades."
}

$md = @"
# Codex Trace Grades

- Status: $status
- Result manifest: $evalPath
- Grade manifest: $gradesPath
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
    summary = "Codex trace eval grading completed."
    grade_status = $status
    manifests = [ordered]@{
        result = $evalPath
        grade = $gradesPath
    }
    artifacts = @($gradesPath, $summaryPath) + $caseGradeArtifacts.ToArray()
} | ConvertTo-Json -Depth 8 -Compress
