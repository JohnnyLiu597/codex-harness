param(
    [string]$Root = "",
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Prompt,
    [string]$Expected = "",
    [string[]]$MustInclude = @(),
    [string[]]$MustNotInclude = @(),
    [string]$Lane = "regression",
    [int]$MinScore = 75,
    [switch]$Disabled
)

$ErrorActionPreference = "Stop"

if (-not $Root) {
    $Root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
} else {
    $Root = (Resolve-Path -LiteralPath $Root).Path
}

$isGlobalHarness = (Test-Path -LiteralPath (Join-Path $Root "config.toml")) -and
    (Test-Path -LiteralPath (Join-Path $Root "harness-evals\trace-evals"))

$promptFile = if ($isGlobalHarness) {
    Join-Path $Root "harness-evals\trace-evals\prompts.csv"
} else {
    Join-Path $Root "evals\prompts.csv"
}

if (-not (Test-Path -LiteralPath $promptFile)) {
    throw "Trace eval prompt file not found: $promptFile"
}

$safeName = ([regex]::Replace($Name.ToLowerInvariant(), '[^a-z0-9]+', '-')).Trim('-')
if (-not $safeName) { $safeName = "trace-eval" }
$id = "$((Get-Date).ToString('yyyyMMdd-HHmmss'))-$safeName"

$rows = @(Import-Csv -LiteralPath $promptFile)
$columns = if ($rows.Count -gt 0) {
    @($rows[0].PSObject.Properties.Name)
} else {
    @("id", "enabled", "kind", "prompt", "expected", "must_include", "must_not_include", "min_score")
}

$laneColumn = if ($columns -contains "lane") { "lane" } elseif ($columns -contains "kind") { "kind" } else { "kind" }

$entry = [ordered]@{}
foreach ($column in $columns) {
    switch ($column) {
        "id" { $entry[$column] = $id }
        "enabled" { $entry[$column] = if ($Disabled) { "false" } else { "true" } }
        "lane" { $entry[$column] = $Lane }
        "kind" { $entry[$column] = $Lane }
        "prompt" { $entry[$column] = $Prompt }
        "expected" { $entry[$column] = $Expected }
        "must_include" { $entry[$column] = ($MustInclude -join "|") }
        "must_not_include" { $entry[$column] = ($MustNotInclude -join "|") }
        "min_score" { $entry[$column] = [string]$MinScore }
        default { $entry[$column] = "" }
    }
}

$rows += [pscustomobject]$entry
$rows | Export-Csv -LiteralPath $promptFile -NoTypeInformation -Encoding UTF8

$caseRoot = if ($isGlobalHarness) {
    Join-Path $Root "harness-evals\trace-evals\cases"
} else {
    Join-Path $Root "evals\cases"
}
New-Item -ItemType Directory -Force -Path $caseRoot | Out-Null
$casePath = Join-Path $caseRoot "$id.md"
$md = @"
# Trace Eval Intake

- ID: $id
- Name: $Name
- Lane: $Lane
- Enabled: $(-not $Disabled)
- Prompt file: $promptFile
- Created: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))

## Expected

$Expected

## Must Include

$($MustInclude -join "`r`n")

## Must Not Include

$($MustNotInclude -join "`r`n")

## Prompt

$Prompt
"@
Set-Content -LiteralPath $casePath -Value $md -Encoding UTF8

[ordered]@{
    status = "success"
    id = $id
    prompt_file = $promptFile
    case_file = $casePath
    lane_column = $laneColumn
} | ConvertTo-Json -Depth 5 -Compress
