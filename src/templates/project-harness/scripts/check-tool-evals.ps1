param(
    [string]$CaseRoot = ""
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
if (-not $CaseRoot) {
    $CaseRoot = Join-Path $root "evals\tool-evals\cases"
}

if (-not (Test-Path -LiteralPath $CaseRoot)) {
    throw "Tool eval case root not found: $CaseRoot"
}

$allowedLanes = @("tool-selection", "param-mapping", "multi-turn", "safety", "tool-error")
$caseFiles = @(Get-ChildItem -LiteralPath $CaseRoot -Recurse -File | Where-Object {
    $_.Extension -in @(".json", ".yaml", ".yml")
})
if ($caseFiles.Count -eq 0) {
    throw "No tool eval cases found under: $CaseRoot"
}

$issues = New-Object System.Collections.Generic.List[string]
$cases = New-Object System.Collections.Generic.List[object]

function Test-HasNonEmptyItems {
    param([object]$Value)

    if ($null -eq $Value) { return $false }
    foreach ($item in @($Value)) {
        if ($null -ne $item -and -not [string]::IsNullOrWhiteSpace([string]$item)) {
            return $true
        }
    }
    return $false
}

function Test-ExpectedHasAssertion {
    param([object]$Expected)

    if ($null -eq $Expected) { return $false }
    foreach ($name in @("tool", "arguments", "must_include", "must_not_include", "allow")) {
        if ($Expected.PSObject.Properties.Name -contains $name) {
            $value = $Expected.$name
            if ($name -eq "allow" -and $null -ne $value) { return $true }
            if (Test-HasNonEmptyItems $value) { return $true }
        }
    }
    return $false
}

function Get-LocalRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $resolvedBase = (Resolve-Path -LiteralPath $BasePath).Path.TrimEnd('\', '/')
    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    if ($resolvedPath.StartsWith($resolvedBase, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $resolvedPath.Substring($resolvedBase.Length).TrimStart('\', '/')
    }
    return $resolvedPath
}

function Get-YamlScalar {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Key
    )

    $match = [regex]::Match($Text, "(?m)^\s*$([regex]::Escape($Key))\s*:\s*(.+?)\s*$")
    if (-not $match.Success) { return "" }
    return $match.Groups[1].Value.Trim().Trim('"').Trim("'")
}

foreach ($file in $caseFiles) {
    $rel = Get-LocalRelativePath -BasePath $root -Path $file.FullName
    if ($file.Extension -eq ".json") {
        try {
            $case = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        } catch {
            $issues.Add("${rel}: invalid JSON - $($_.Exception.Message)") | Out-Null
            continue
        }

        foreach ($field in @("schema", "id", "enabled", "lane", "description", "prompt", "expected")) {
            if ($null -eq $case.$field -or [string]::IsNullOrWhiteSpace([string]$case.$field)) {
                $issues.Add("${rel}: missing $field") | Out-Null
            }
        }
        if ($case.schema -ne "codex-tool-eval-case-v1") {
            $issues.Add("${rel}: unexpected schema $($case.schema)") | Out-Null
        }
        if ($case.lane -notin $allowedLanes) {
            $issues.Add("${rel}: lane must be one of $($allowedLanes -join ', ')") | Out-Null
        }
        if ($case.enabled -eq $true -and -not (Test-ExpectedHasAssertion $case.expected)) {
            $issues.Add("${rel}: enabled case needs at least one expected assertion") | Out-Null
        }
        if ($case.lane -eq "safety" -and $case.enabled -eq $true -and -not ($case.expected.PSObject.Properties.Name -contains "allow")) {
            $issues.Add("${rel}: safety cases should include expected.allow") | Out-Null
        }
        $cases.Add([pscustomobject]@{
            id = $case.id
            enabled = [bool]$case.enabled
            lane = $case.lane
            path = $rel
            format = "json"
        }) | Out-Null
        continue
    }

    $text = Get-Content -LiteralPath $file.FullName -Raw
    $schema = Get-YamlScalar -Text $text -Key "schema"
    $id = Get-YamlScalar -Text $text -Key "id"
    $enabledText = Get-YamlScalar -Text $text -Key "enabled"
    $lane = Get-YamlScalar -Text $text -Key "lane"
    $description = Get-YamlScalar -Text $text -Key "description"
    $prompt = Get-YamlScalar -Text $text -Key "prompt"

    foreach ($pair in @(
        @{ key = "schema"; value = $schema },
        @{ key = "id"; value = $id },
        @{ key = "enabled"; value = $enabledText },
        @{ key = "lane"; value = $lane },
        @{ key = "description"; value = $description },
        @{ key = "prompt"; value = $prompt }
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$pair.value)) {
            $issues.Add("${rel}: missing $($pair.key)") | Out-Null
        }
    }

    if ($schema -ne "codex-tool-eval-case-v1") {
        $issues.Add("${rel}: unexpected schema $schema") | Out-Null
    }
    if ($lane -notin $allowedLanes) {
        $issues.Add("${rel}: lane must be one of $($allowedLanes -join ', ')") | Out-Null
    }
    $enabled = $enabledText -eq "true"
    $hasExpected = $text -match '(?m)^\s*expected\s*:' -and $text -match '(?m)^\s{2,}(tool|arguments|must_include|must_not_include|allow)\s*:'
    if ($enabled -and -not $hasExpected) {
        $issues.Add("${rel}: enabled YAML case needs at least one expected assertion") | Out-Null
    }
    if ($lane -eq "safety" -and $enabled -and $text -notmatch '(?m)^\s{2,}allow\s*:') {
        $issues.Add("${rel}: safety cases should include expected.allow") | Out-Null
    }

    $cases.Add([pscustomobject]@{
        id = $id
        enabled = $enabled
        lane = $lane
        path = $rel
        format = "yaml"
    }) | Out-Null
}

if ($issues.Count -gt 0) {
    throw "Tool eval cases are invalid: $($issues -join '; ')"
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runDir = Join-Path $root ("artifacts\tool-eval-checks\" + $stamp)
$jsonPath = Join-Path $runDir "tool-evals-check.json"
$summaryPath = Join-Path $runDir "summary.md"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$enabledCount = @($cases | Where-Object { $_.enabled }).Count
$laneCounts = @{}
foreach ($case in $cases) {
    if (-not $laneCounts.ContainsKey($case.lane)) { $laneCounts[$case.lane] = 0 }
    $laneCounts[$case.lane] += 1
}

[ordered]@{
    schema = "codex-tool-evals-check-v1"
    status = "passed"
    created_at = (Get-Date).ToString("o")
    case_root = $CaseRoot
    total = $cases.Count
    enabled = $enabledCount
    lanes = $laneCounts
    cases = $cases.ToArray()
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$caseLines = ($cases | ForEach-Object { "- $($_.id): $($_.lane), enabled=$($_.enabled), $($_.format), $($_.path)" }) -join "`r`n"

$md = @"
# Tool Evals Check

- Status: passed
- Total cases: $($cases.Count)
- Enabled cases: $enabledCount

## Cases

$caseLines
"@

Set-Content -LiteralPath $summaryPath -Value $md -Encoding UTF8

[ordered]@{
    status = "success"
    summary = "Tool eval fixtures validated."
    total = $cases.Count
    enabled = $enabledCount
    artifacts = @($jsonPath, $summaryPath)
} | ConvertTo-Json -Depth 5 -Compress
