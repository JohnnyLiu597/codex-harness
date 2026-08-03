param(
    [string]$ProjectRoot = ".",
    [string]$CodexHome = "$env:USERPROFILE\.codex",
    [int]$AnchorByteBudget = 16384,
    [int]$AnchorLineBudget = 400,
    [int]$AnchorTotalByteBudget = 65536,
    [int]$AnchorTotalLineBudget = 1600,
    [int]$AgentByteBudget = 24576,
    [int]$AgentLineBudget = 600,
    [int]$AgentTotalByteBudget = 65536,
    [int]$AgentTotalLineBudget = 1600,
    [int]$SkillMetadataByteBudget = 4096,
    [int]$SkillMetadataLineBudget = 80,
    [int]$SkillByteBudget = 32768,
    [int]$SkillLineBudget = 800
)

$ErrorActionPreference = "Stop"

function Get-LineCount {
    param([AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return 0 }
    $newlineCount = [regex]::Matches($Text, "\r\n|\n|\r").Count
    if ($Text -match "(\r\n|\n|\r)$") { return $newlineCount }
    return ($newlineCount + 1)
}

function Get-FileMeasure {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-Item -LiteralPath $Path -Force
    $text = [System.IO.File]::ReadAllText($item.FullName)
    return [pscustomobject]@{
        path = $item.FullName
        bytes = [long]$item.Length
        lines = [int](Get-LineCount -Text $text)
        text = $text
    }
}

function Get-RelativePathLabel {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $base = [System.IO.Path]::GetFullPath($BasePath).TrimEnd("\", "/")
    $full = [System.IO.Path]::GetFullPath($Path)
    $prefix = $base + [System.IO.Path]::DirectorySeparatorChar
    if ($full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($prefix.Length).Replace("\", "/")
    }
    if ($full.Equals($base, [System.StringComparison]::OrdinalIgnoreCase)) {
        return "."
    }
    return $full
}

function Add-Warning {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$List,
        [Parameter(Mandatory = $true)][string]$Code,
        [string]$Path = "",
        [Parameter(Mandatory = $true)][string]$Message
    )

    $List.Add([pscustomobject]@{
        code = $Code
        path = $Path
        message = $Message
    }) | Out-Null
}

function Get-SafeSkillFiles {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    $forbiddenDirectories = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @(
        ".codex-trash",
        ".git",
        "artifacts",
        "backups",
        "browser",
        "browser-state",
        "cache",
        "caches",
        "logs",
        "plugins",
        "sessions"
    )) {
        $forbiddenDirectories.Add($name) | Out-Null
    }

    $rootItem = Get-Item -LiteralPath $RootPath -Force
    if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        return @()
    }

    $pending = New-Object "System.Collections.Generic.Queue[string]"
    $results = New-Object "System.Collections.Generic.List[System.IO.FileInfo]"
    $pending.Enqueue($RootPath)
    while ($pending.Count -gt 0) {
        $currentPath = $pending.Dequeue()
        foreach ($file in @(Get-ChildItem -LiteralPath $currentPath -Filter "SKILL.md" -File -Force | Sort-Object FullName)) {
            $results.Add($file) | Out-Null
        }
        foreach ($directory in @(Get-ChildItem -LiteralPath $currentPath -Directory -Force | Sort-Object FullName)) {
            if (($directory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            if ($forbiddenDirectories.Contains($directory.Name)) { continue }
            $pending.Enqueue($directory.FullName)
        }
    }

    return @($results.ToArray() | Sort-Object FullName)
}

$budgetValues = @(
    $AnchorByteBudget,
    $AnchorLineBudget,
    $AnchorTotalByteBudget,
    $AnchorTotalLineBudget,
    $AgentByteBudget,
    $AgentLineBudget,
    $AgentTotalByteBudget,
    $AgentTotalLineBudget,
    $SkillMetadataByteBudget,
    $SkillMetadataLineBudget,
    $SkillByteBudget,
    $SkillLineBudget
)
if (@($budgetValues | Where-Object { $_ -le 0 }).Count -gt 0) {
    throw "All context budget values must be greater than zero."
}

if ($ProjectRoot -eq ".") {
    $scriptProjectRoot = Join-Path $PSScriptRoot ".."
    if ((Test-Path -LiteralPath (Join-Path $scriptProjectRoot "mission.md")) -and
        (Test-Path -LiteralPath (Join-Path $scriptProjectRoot "CONTEXT.md"))) {
        $ProjectRoot = $scriptProjectRoot
    }
}

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$codexHomePath = if (Test-Path -LiteralPath $CodexHome) {
    (Resolve-Path -LiteralPath $CodexHome).Path
} else {
    [System.IO.Path]::GetFullPath($CodexHome)
}

$warnings = New-Object System.Collections.Generic.List[object]
$anchorRecords = New-Object System.Collections.Generic.List[object]
$agentRecords = New-Object System.Collections.Generic.List[object]
$skillRecords = New-Object System.Collections.Generic.List[object]

$anchorDefinitions = @(
    [pscustomobject]@{ path = "mission.md"; required = $true },
    [pscustomobject]@{ path = "CONTEXT.md"; required = $true },
    [pscustomobject]@{ path = ".agent\rules.md"; required = $false },
    [pscustomobject]@{ path = "MEMORY.md"; required = $true },
    [pscustomobject]@{ path = "README.md"; required = $false },
    [pscustomobject]@{ path = "docs\project.md"; required = $false },
    [pscustomobject]@{ path = "docs\architecture.md"; required = $false },
    [pscustomobject]@{ path = "docs\commands.md"; required = $false }
)

foreach ($definition in $anchorDefinitions) {
    $path = Join-Path $root $definition.path
    $label = $definition.path.Replace("\", "/")
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $anchorRecords.Add([pscustomobject]@{
            path = $label
            present = $false
            required = [bool]$definition.required
            bytes = 0
            lines = 0
            byte_budget = $AnchorByteBudget
            line_budget = $AnchorLineBudget
            within_budget = $null
        }) | Out-Null
        if ($definition.required) {
            Add-Warning -List $warnings -Code "anchor_missing" -Path $label -Message "Required project anchor is missing."
        }
        continue
    }

    $measure = Get-FileMeasure -Path $path
    $withinBudget = ($measure.bytes -le $AnchorByteBudget -and $measure.lines -le $AnchorLineBudget)
    $anchorRecords.Add([pscustomobject]@{
        path = $label
        present = $true
        required = [bool]$definition.required
        bytes = $measure.bytes
        lines = $measure.lines
        byte_budget = $AnchorByteBudget
        line_budget = $AnchorLineBudget
        within_budget = $withinBudget
    }) | Out-Null

    if ($measure.bytes -gt $AnchorByteBudget) {
        Add-Warning -List $warnings -Code "anchor_bytes_exceeded" -Path $label -Message "Project anchor exceeds its byte budget."
    }
    if ($measure.lines -gt $AnchorLineBudget) {
        Add-Warning -List $warnings -Code "anchor_lines_exceeded" -Path $label -Message "Project anchor exceeds its line budget."
    }
}

$seenAgentPaths = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
$agentCandidates = New-Object System.Collections.Generic.List[object]
$globalAgents = Join-Path $codexHomePath "AGENTS.md"
if (Test-Path -LiteralPath $globalAgents -PathType Leaf) {
    $agentCandidates.Add([pscustomobject]@{
        scope = "codex-home"
        path = (Resolve-Path -LiteralPath $globalAgents).Path
    }) | Out-Null
}

$ancestorPaths = New-Object System.Collections.Generic.List[string]
$current = Get-Item -LiteralPath $root
while ($null -ne $current) {
    $candidate = Join-Path $current.FullName "AGENTS.md"
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $ancestorPaths.Add((Resolve-Path -LiteralPath $candidate).Path) | Out-Null
    }
    $current = $current.Parent
}
$orderedAncestors = $ancestorPaths.ToArray()
[array]::Reverse($orderedAncestors)
foreach ($path in $orderedAncestors) {
    $scope = if ((Split-Path -Parent $path).Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        "project"
    } else {
        "ancestor"
    }
    $agentCandidates.Add([pscustomobject]@{ scope = $scope; path = $path }) | Out-Null
}

$layer = 0
foreach ($candidate in $agentCandidates) {
    if (-not $seenAgentPaths.Add($candidate.path)) { continue }
    $measure = Get-FileMeasure -Path $candidate.path
    $label = if ($candidate.scope -eq "codex-home") {
        "<codex-home>/AGENTS.md"
    } else {
        Get-RelativePathLabel -BasePath $root -Path $candidate.path
    }
    $withinBudget = ($measure.bytes -le $AgentByteBudget -and $measure.lines -le $AgentLineBudget)
    $agentRecords.Add([pscustomobject]@{
        layer = $layer
        scope = $candidate.scope
        path = $label
        bytes = $measure.bytes
        lines = $measure.lines
        byte_budget = $AgentByteBudget
        line_budget = $AgentLineBudget
        within_budget = $withinBudget
    }) | Out-Null
    $layer++

    if ($measure.bytes -gt $AgentByteBudget) {
        Add-Warning -List $warnings -Code "agents_bytes_exceeded" -Path $label -Message "AGENTS layer exceeds its byte budget."
    }
    if ($measure.lines -gt $AgentLineBudget) {
        Add-Warning -List $warnings -Code "agents_lines_exceeded" -Path $label -Message "AGENTS layer exceeds its line budget."
    }
}
if ($agentRecords.Count -eq 0) {
    Add-Warning -List $warnings -Code "agents_missing" -Message "No effective AGENTS.md layer was found."
}

$skillRoots = New-Object System.Collections.Generic.List[object]
$globalSkillRoot = Join-Path $codexHomePath "skills"
if (Test-Path -LiteralPath $globalSkillRoot -PathType Container) {
    $skillRoots.Add([pscustomobject]@{ scope = "codex-home"; path = (Resolve-Path -LiteralPath $globalSkillRoot).Path }) | Out-Null
}
foreach ($candidate in @((Join-Path $root ".codex\skills"), (Join-Path $root "skills"))) {
    if (Test-Path -LiteralPath $candidate -PathType Container) {
        $skillRoots.Add([pscustomobject]@{ scope = "project"; path = (Resolve-Path -LiteralPath $candidate).Path }) | Out-Null
    }
}

$seenSkillRoots = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
$seenSkillFiles = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($skillRoot in @($skillRoots | Sort-Object scope, path)) {
    if (-not $seenSkillRoots.Add($skillRoot.path)) { continue }
    try {
        $skillFiles = @(Get-SafeSkillFiles -RootPath $skillRoot.path)
    } catch {
        Add-Warning -List $warnings -Code "skill_root_unreadable" -Path $skillRoot.path -Message "Known skill root could not be enumerated."
        continue
    }

    foreach ($skillFile in $skillFiles) {
        if (-not $seenSkillFiles.Add($skillFile.FullName)) { continue }
        $measure = Get-FileMeasure -Path $skillFile.FullName
        $metadataMatch = [regex]::Match(
            $measure.text,
            "\A(?:\uFEFF)?---(?:\r\n|\n|\r)(?<body>.*?)(?:\r\n|\n|\r)---(?:(?:\r\n|\n|\r)|\z)",
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )
        $metadataText = if ($metadataMatch.Success) { $metadataMatch.Value } else { "" }
        $metadataBytes = [System.Text.Encoding]::UTF8.GetByteCount($metadataText)
        $metadataLines = Get-LineCount -Text $metadataText
        $label = (Get-RelativePathLabel -BasePath $skillRoot.path -Path $skillFile.FullName)
        $skillName = Split-Path -Leaf (Split-Path -Parent $skillFile.FullName)
        $metadataWithinBudget = (
            $metadataMatch.Success -and
            $metadataBytes -le $SkillMetadataByteBudget -and
            $metadataLines -le $SkillMetadataLineBudget
        )
        $fullWithinBudget = ($measure.bytes -le $SkillByteBudget -and $measure.lines -le $SkillLineBudget)

        $skillRecords.Add([pscustomobject]@{
            scope = $skillRoot.scope
            skill = $skillName
            path = $label
            metadata_present = $metadataMatch.Success
            metadata_bytes = $metadataBytes
            metadata_lines = $metadataLines
            metadata_byte_budget = $SkillMetadataByteBudget
            metadata_line_budget = $SkillMetadataLineBudget
            metadata_within_budget = $metadataWithinBudget
            full_bytes = $measure.bytes
            full_lines = $measure.lines
            full_byte_budget = $SkillByteBudget
            full_line_budget = $SkillLineBudget
            full_within_budget = $fullWithinBudget
        }) | Out-Null

        if (-not $metadataMatch.Success) {
            Add-Warning -List $warnings -Code "skill_metadata_missing" -Path $label -Message "SKILL.md has no leading metadata block."
        } else {
            if ($metadataBytes -gt $SkillMetadataByteBudget) {
                Add-Warning -List $warnings -Code "skill_metadata_bytes_exceeded" -Path $label -Message "Skill metadata exceeds its byte budget."
            }
            if ($metadataLines -gt $SkillMetadataLineBudget) {
                Add-Warning -List $warnings -Code "skill_metadata_lines_exceeded" -Path $label -Message "Skill metadata exceeds its line budget."
            }
        }
        if ($measure.bytes -gt $SkillByteBudget) {
            Add-Warning -List $warnings -Code "skill_bytes_exceeded" -Path $label -Message "Full SKILL.md exceeds its byte budget."
        }
        if ($measure.lines -gt $SkillLineBudget) {
            Add-Warning -List $warnings -Code "skill_lines_exceeded" -Path $label -Message "Full SKILL.md exceeds its line budget."
        }
    }
}

$anchorBytes = [long](($anchorRecords | Measure-Object -Property bytes -Sum).Sum)
$anchorLines = [long](($anchorRecords | Measure-Object -Property lines -Sum).Sum)
$agentBytes = [long](($agentRecords | Measure-Object -Property bytes -Sum).Sum)
$agentLines = [long](($agentRecords | Measure-Object -Property lines -Sum).Sum)
$skillMetadataBytes = [long](($skillRecords | Measure-Object -Property metadata_bytes -Sum).Sum)
$skillMetadataLines = [long](($skillRecords | Measure-Object -Property metadata_lines -Sum).Sum)
$skillFullBytes = [long](($skillRecords | Measure-Object -Property full_bytes -Sum).Sum)
$skillFullLines = [long](($skillRecords | Measure-Object -Property full_lines -Sum).Sum)

if ($anchorBytes -gt $AnchorTotalByteBudget) {
    Add-Warning -List $warnings -Code "anchor_total_bytes_exceeded" -Message "Project anchors exceed their combined byte budget."
}
if ($anchorLines -gt $AnchorTotalLineBudget) {
    Add-Warning -List $warnings -Code "anchor_total_lines_exceeded" -Message "Project anchors exceed their combined line budget."
}
if ($agentBytes -gt $AgentTotalByteBudget) {
    Add-Warning -List $warnings -Code "agents_total_bytes_exceeded" -Message "AGENTS layers exceed their combined byte budget."
}
if ($agentLines -gt $AgentTotalLineBudget) {
    Add-Warning -List $warnings -Code "agents_total_lines_exceeded" -Message "AGENTS layers exceed their combined line budget."
}

$record = [ordered]@{
    schema = "codex-context-budget-audit-v1"
    status = if ($warnings.Count -eq 0) { "passed" } else { "warning" }
    read_only = $true
    project_root = $root
    codex_home = $codexHomePath
    budgets = [ordered]@{
        project_anchor = [ordered]@{
            per_file_bytes = $AnchorByteBudget
            per_file_lines = $AnchorLineBudget
            total_bytes = $AnchorTotalByteBudget
            total_lines = $AnchorTotalLineBudget
        }
        agents_layer = [ordered]@{
            per_file_bytes = $AgentByteBudget
            per_file_lines = $AgentLineBudget
            total_bytes = $AgentTotalByteBudget
            total_lines = $AgentTotalLineBudget
        }
        skill = [ordered]@{
            metadata_bytes = $SkillMetadataByteBudget
            metadata_lines = $SkillMetadataLineBudget
            full_bytes = $SkillByteBudget
            full_lines = $SkillLineBudget
        }
    }
    totals = [ordered]@{
        project_anchors = [ordered]@{ bytes = $anchorBytes; lines = $anchorLines; count = $anchorRecords.Count }
        agents_layers = [ordered]@{ bytes = $agentBytes; lines = $agentLines; count = $agentRecords.Count }
        skill_metadata = [ordered]@{ bytes = $skillMetadataBytes; lines = $skillMetadataLines; count = $skillRecords.Count }
        full_skills = [ordered]@{ bytes = $skillFullBytes; lines = $skillFullLines; count = $skillRecords.Count }
    }
    project_anchors = $anchorRecords.ToArray()
    agents_layers = $agentRecords.ToArray()
    skills = $skillRecords.ToArray()
    warnings = $warnings.ToArray()
}

$record | ConvertTo-Json -Depth 12
