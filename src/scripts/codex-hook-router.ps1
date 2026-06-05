param(
    [ValidateSet("Stop", "SessionStart", "SessionEnd", "PreToolUse", "PostToolUse", "PreCompact", "ToolFailure")]
    [string]$Event = "Stop",
    [string]$Payload = "",
    [string]$CodexHome = "$env:USERPROFILE\.codex",
    [string]$LogRoot = "",
    [switch]$Quiet
)

$ErrorActionPreference = "SilentlyContinue"

function Get-Sha256Text {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return "" }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $hash = $sha.ComputeHash($bytes)
    return ([System.BitConverter]::ToString($hash)).Replace("-", "").ToLowerInvariant()
}

function Get-JsonPayloadFacts {
    param([string]$Text)

    $facts = [ordered]@{
        keys = @()
        summary = "Task completed."
        status = ""
        payload_sha256 = Get-Sha256Text -Text $Text
        parse_status = if ([string]::IsNullOrWhiteSpace($Text)) { "empty" } else { "raw" }
    }

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $facts
    }

    try {
        $json = $Text | ConvertFrom-Json
        $facts.parse_status = "json"
        $facts.keys = @($json.PSObject.Properties | ForEach-Object { $_.Name })
        if ($json.message) {
            $facts.summary = [string]$json.message
        } elseif ($json.summary) {
            $facts.summary = [string]$json.summary
        } elseif ($json.status) {
            $facts.summary = "Codex finished with status: $($json.status)"
        }
        if ($json.status) {
            $facts.status = [string]$json.status
        }
    } catch {
        $facts.summary = "Hook payload received as non-JSON text."
    }

    if ([string]::IsNullOrWhiteSpace($facts.summary)) {
        $facts.summary = "Task completed."
    }

    return $facts
}

function Get-GitFacts {
    param([string]$Root)

    $facts = [ordered]@{
        is_git_repo = $false
        dirty = $null
        changed_count = 0
        branch = ""
        head = ""
    }

    try {
        $inside = git -C $Root rev-parse --is-inside-work-tree 2>$null
        if ($inside -ne "true") { return $facts }
        $facts.is_git_repo = $true
        $facts.branch = [string](git -C $Root branch --show-current 2>$null)
        $facts.head = [string](git -C $Root rev-parse --short HEAD 2>$null)
        $changes = @(git -C $Root status --porcelain=v1 2>$null)
        $facts.changed_count = $changes.Count
        $facts.dirty = $changes.Count -gt 0
    } catch {
        return $facts
    }

    return $facts
}

function Get-ProjectFacts {
    param([string]$Root)

    $anchors = @("AGENTS.md", "mission.md", "CONTEXT.md", "MEMORY.md", "README.md", "docs\testing.md", "docs\smoke.md")
    $present = @()
    foreach ($rel in $anchors) {
        if (Test-Path -LiteralPath (Join-Path $Root $rel)) {
            $present += $rel
        }
    }

    return [ordered]@{
        harness_files_present = $present
        has_project_harness = $present.Count -gt 0
    }
}

function Get-CodexHarnessDriftFacts {
    param(
        [string]$Root,
        [string]$CodexHomePath
    )

    $sourceRoot = $env:CODEX_HARNESS_SOURCE
    $isCodexHarness = $false
    if (-not [string]::IsNullOrWhiteSpace($sourceRoot)) {
        try {
            $sourceRoot = (Resolve-Path -LiteralPath $sourceRoot).Path
        } catch {
            $sourceRoot = ""
        }
    }
    try {
        $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
        $isCodexHarness = (-not [string]::IsNullOrWhiteSpace($sourceRoot)) -and
            $resolvedRoot.StartsWith($sourceRoot, [System.StringComparison]::OrdinalIgnoreCase)
    } catch {
        $isCodexHarness = $false
    }

    $runtimeSkill = Join-Path $CodexHomePath "skills\project-harness-optimizer\SKILL.md"
    $sourceSkill = if ([string]::IsNullOrWhiteSpace($sourceRoot)) {
        ""
    } else {
        Join-Path $sourceRoot "src\skills\project-harness-optimizer\SKILL.md"
    }
    $skillDrift = $null
    if ((Test-Path -LiteralPath $runtimeSkill) -and $sourceSkill -and (Test-Path -LiteralPath $sourceSkill)) {
        try {
            $skillDrift = (Get-FileHash -LiteralPath $runtimeSkill -Algorithm SHA256).Hash -ne
                (Get-FileHash -LiteralPath $sourceSkill -Algorithm SHA256).Hash
        } catch {
            $skillDrift = $null
        }
    }

    return [ordered]@{
        source_root = $sourceRoot
        current_repo_is_codex_harness = $isCodexHarness
        project_harness_optimizer_drift = $skillDrift
    }
}

function Get-Recommendations {
    param(
        [string]$EventName,
        [hashtable]$PayloadFacts,
        [hashtable]$GitFacts,
        [hashtable]$ProjectFacts,
        [hashtable]$DriftFacts
    )

    $items = New-Object System.Collections.Generic.List[string]

    if ($GitFacts.is_git_repo -and $GitFacts.dirty) {
        $items.Add("Run the smallest meaningful verification before final handoff.") | Out-Null
    }
    if ($ProjectFacts.has_project_harness -and $GitFacts.dirty) {
        $items.Add("For substantial work, update CONTEXT.md or create a session summary before stopping.") | Out-Null
    }
    if ($DriftFacts.current_repo_is_codex_harness -and $DriftFacts.project_harness_optimizer_drift) {
        $items.Add("Runtime/source drift detected for project-harness-optimizer; run deploy\sync-from-runtime.ps1 -Refresh after runtime verification.") | Out-Null
    }
    if ($PayloadFacts.status -match 'fail|error|blocked') {
        $items.Add("If this was a repeated tool or harness failure, record it with scripts\new-tool-failure.ps1.") | Out-Null
    }
    if ($EventName -eq "PreCompact") {
        $items.Add("Create a concise session summary before context compaction.") | Out-Null
    }

    return $items.ToArray()
}

$codexHomePath = if (Test-Path -LiteralPath $CodexHome) {
    (Resolve-Path -LiteralPath $CodexHome).Path
} else {
    $CodexHome
}

if (-not $LogRoot) {
    $LogRoot = Join-Path $codexHomePath "hook-logs"
}
if (-not (Test-Path -LiteralPath $LogRoot)) {
    New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
}

$cwd = (Get-Location).Path
$timestamp = (Get-Date).ToUniversalTime().ToString("o")
$date = Get-Date -Format "yyyyMMdd"
$payloadFacts = Get-JsonPayloadFacts -Text $Payload
$gitFacts = Get-GitFacts -Root $cwd
$projectFacts = Get-ProjectFacts -Root $cwd
$driftFacts = Get-CodexHarnessDriftFacts -Root $cwd -CodexHomePath $codexHomePath
$recommendations = Get-Recommendations -EventName $Event -PayloadFacts $payloadFacts -GitFacts $gitFacts -ProjectFacts $projectFacts -DriftFacts $driftFacts

$logPath = Join-Path $LogRoot ("hook-$($Event.ToLowerInvariant())-$date.jsonl")
$latestPath = Join-Path $LogRoot "latest-stop.txt"
if ($Event -ne "Stop") {
    $latestPath = Join-Path $LogRoot "latest-hook.txt"
}

$entry = [ordered]@{
    schema = "codex-hook-event-v1"
    ts = $timestamp
    event = $Event
    cwd = $cwd
    summary = $payloadFacts.summary
    status = if ($payloadFacts.status) { $payloadFacts.status } else { "success" }
    git = $gitFacts
    project = $projectFacts
    codex_harness = $driftFacts
    payload = [ordered]@{
        parse_status = $payloadFacts.parse_status
        keys = $payloadFacts.keys
        sha256 = $payloadFacts.payload_sha256
    }
    recommendations = $recommendations
    artifacts = @($logPath, $latestPath)
}

$json = $entry | ConvertTo-Json -Depth 20 -Compress
Add-Content -LiteralPath $logPath -Value $json -Encoding UTF8

$summaryLines = @(
    "Last Codex hook: $timestamp",
    "Event: $Event",
    "CWD: $cwd",
    "Summary: $($payloadFacts.summary)",
    "Git dirty: $($gitFacts.dirty)",
    "Changed count: $($gitFacts.changed_count)"
)
if ($recommendations.Count -gt 0) {
    $summaryLines += "Recommendations:"
    $summaryLines += @($recommendations | ForEach-Object { "- $_" })
}

Set-Content -LiteralPath $latestPath -Value ($summaryLines -join "`r`n") -Encoding UTF8

if (-not $Quiet) {
    [ordered]@{
        status = "success"
        summary = "Codex hook event recorded."
        event = $Event
        artifacts = @($logPath, $latestPath)
        recommendations = $recommendations
    } | ConvertTo-Json -Depth 8 -Compress
}

exit 0
