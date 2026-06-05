param(
    [string]$CodexHome = "$env:USERPROFILE\.codex",
    [string]$ProjectRoot = "",
    [int]$MaxActiveSkills = 50,
    [int]$LargeSkillBytes = 12000
)

$ErrorActionPreference = "Stop"

$codexHomePath = (Resolve-Path -LiteralPath $CodexHome).Path
if (-not $ProjectRoot) {
    $scriptProjectRoot = Join-Path $PSScriptRoot ".."
    if ((Test-Path -LiteralPath (Join-Path $scriptProjectRoot "mission.md")) -and
        (Test-Path -LiteralPath (Join-Path $scriptProjectRoot "CONTEXT.md"))) {
        $ProjectRoot = $scriptProjectRoot
    }
}
$skillRoots = New-Object System.Collections.Generic.List[string]
$globalSkills = Join-Path $codexHomePath "skills"
if (Test-Path -LiteralPath $globalSkills) { $skillRoots.Add($globalSkills) | Out-Null }

if ($ProjectRoot) {
    $projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
    foreach ($candidate in @((Join-Path $projectPath ".codex\skills"), (Join-Path $projectPath "skills"))) {
        if (Test-Path -LiteralPath $candidate) { $skillRoots.Add($candidate) | Out-Null }
    }
}

$records = New-Object System.Collections.Generic.List[object]
$providerPattern = '(external agent runtime|external runtime|provider-specific runtime|model-provider-specific)'

foreach ($root in $skillRoots) {
    foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -Force)) {
        if ($dir.Name -in @(".system", "codex-primary-runtime")) { continue }
        $skillPath = Join-Path $dir.FullName "SKILL.md"
        $hasSkill = Test-Path -LiteralPath $skillPath
        $text = if ($hasSkill) { Get-Content -LiteralPath $skillPath -Raw } else { "" }
        $name = $dir.Name
        $description = ""
        if ($text -match '(?ms)^---\s*(.*?)\s*---') {
            $front = $Matches[1]
            if ($front -match '(?m)^name:\s*(.+)$') { $name = $Matches[1].Trim() }
            if ($front -match '(?m)^description:\s*(.+)$') { $description = $Matches[1].Trim() }
        }
        $issues = New-Object System.Collections.Generic.List[string]
        if (-not $hasSkill) { $issues.Add("missing SKILL.md") | Out-Null }
        if ($hasSkill -and [string]::IsNullOrWhiteSpace($description)) { $issues.Add("missing description") | Out-Null }
        if ($hasSkill -and $text.Length -gt $LargeSkillBytes) { $issues.Add("large skill") | Out-Null }
        if ($hasSkill -and $text -match $providerPattern) { $issues.Add("provider-specific references") | Out-Null }
        if ($description -match '^(Use when|Use this|Guide for)') {
            # Good enough trigger language; no issue.
        } elseif ($hasSkill -and -not [string]::IsNullOrWhiteSpace($description)) {
            $issues.Add("description may be weak trigger") | Out-Null
        }
        $verdict = if (-not $hasSkill) {
            "Improve"
        } elseif ($issues.Count -eq 0) {
            "Keep"
        } elseif ($issues -contains "provider-specific references" -or $issues -contains "large skill") {
            "Review"
        } else {
            "Improve"
        }
        $records.Add([pscustomobject]@{
            root = $root
            directory = $dir.Name
            name = $name
            description = $description
            bytes = if ($hasSkill) { (Get-Item -LiteralPath $skillPath).Length } else { 0 }
            verdict = $verdict
            issues = $issues.ToArray()
        }) | Out-Null
    }
}

$activeCount = @($records | Where-Object { $_.root -eq $globalSkills }).Count
$missingCount = @($records | Where-Object { $_.issues -contains "missing SKILL.md" }).Count
$providerSpecific = @($records | Where-Object { $_.issues -contains "provider-specific references" })
$largest = @($records | Sort-Object bytes -Descending | Select-Object -First 10)
$warnings = New-Object System.Collections.Generic.List[string]
if ($activeCount -gt $MaxActiveSkills) {
    $warnings.Add("$activeCount active global skills; target is <= $MaxActiveSkills.") | Out-Null
}
if ($missingCount -gt 0) {
    $warnings.Add("$missingCount active skill directories missing SKILL.md.") | Out-Null
}
if ($providerSpecific.Count -gt 0) {
    $warnings.Add("$($providerSpecific.Count) skills contain provider-specific references.") | Out-Null
}

$status = if ($missingCount -gt 0 -or $activeCount -gt $MaxActiveSkills) { "warning" } else { "passed" }
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportDir = Join-Path $codexHomePath ("harness-health\skill-surface\" + $stamp)
if ($ProjectRoot) {
    $reportDir = Join-Path (Resolve-Path -LiteralPath $ProjectRoot).Path ("artifacts\skill-surface\" + $stamp)
}
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$jsonPath = Join-Path $reportDir "skill-surface.json"
$summaryPath = Join-Path $reportDir "summary.md"

$record = [ordered]@{
    schema = "codex-skill-surface-stocktake-v1"
    status = $status
    created_at = (Get-Date).ToString("o")
    codex_home = $codexHomePath
    project_root = $ProjectRoot
    active_global_skill_count = $activeCount
    missing_skill_md_count = $missingCount
    provider_specific_count = $providerSpecific.Count
    warnings = $warnings.ToArray()
    largest = $largest
    skills = $records.ToArray()
}
$record | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$warningLines = if ($warnings.Count -gt 0) { ($warnings | ForEach-Object { "- $_" }) -join "`r`n" } else { "- None." }
$largestLines = if ($largest.Count -gt 0) { ($largest | ForEach-Object { "- $($_.name): $($_.bytes) bytes verdict=$($_.verdict)" }) -join "`r`n" } else { "- None." }
$reviewLines = if (@($records | Where-Object { $_.verdict -ne "Keep" }).Count -gt 0) {
    (@($records | Where-Object { $_.verdict -ne "Keep" } | Select-Object -First 20) | ForEach-Object { "- $($_.verdict): $($_.name) issues=$($_.issues -join '|')" }) -join "`r`n"
} else {
    "- None."
}

$md = @"
# Skill Surface Stocktake

- Status: $status
- Active global skills: $activeCount
- Missing SKILL.md: $missingCount
- Provider-specific matches: $($providerSpecific.Count)
- Created: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))

## Warnings

$warningLines

## Largest Skills

$largestLines

## Review Candidates

$reviewLines
"@
Set-Content -LiteralPath $summaryPath -Value $md -Encoding UTF8

[ordered]@{
    status = if ($status -eq "passed") { "success" } else { "warning" }
    summary = "Skill surface stocktake completed."
    artifacts = @($jsonPath, $summaryPath)
} | ConvertTo-Json -Depth 5 -Compress
