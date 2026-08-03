param(
    [string]$CodexHome = "$env:USERPROFILE\.codex",
    [string]$ProjectRoot = "",
    [switch]$Refresh
)

$ErrorActionPreference = "Stop"

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
} else {
    $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
}

$CodexHome = (Resolve-Path -LiteralPath $CodexHome).Path
$srcRoot = Join-Path $ProjectRoot "src"
$artifactsRoot = Join-Path $ProjectRoot "artifacts"
$refreshBackup = ""

function Copy-FileIfPresent {
    param([string]$RelativePath)

    $source = Join-Path $CodexHome $RelativePath
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { return $false }
    $target = Join-Path $srcRoot $RelativePath
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Copy-Item -LiteralPath $source -Destination $target -Force
    return $true
}

function Copy-MaintainableDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Target,
        [string[]]$ExcludeDirectoryNames = @()
    )

    New-Item -ItemType Directory -Force -Path $Target | Out-Null
    $sourcePrefix = (Get-Item -LiteralPath $Source).FullName.TrimEnd('\') + '\'
    $excludedDirectories = @($ExcludeDirectoryNames) + @(
        "__pycache__",
        ".codex-trash",
        "plugins",
        "plugin",
        "cache",
        "caches",
        "session",
        "sessions",
        "archived_sessions",
        "log",
        "logs",
        "hook-logs",
        "browser",
        "browser-state",
        "browser_state",
        "computer-use",
        "process_manager",
        "harness-health",
        "harness-changes",
        "skills.archived",
        "agents.archived",
        "backups",
        "archived"
    )
    foreach ($file in @(Get-ChildItem -LiteralPath $Source -Recurse -Force -File)) {
        $relative = $file.FullName.Substring($sourcePrefix.Length)
        $segments = $relative -split '[\\/]'
        if (@($segments | Where-Object { $_ -in $excludedDirectories -or $_ -like "backup-*" }).Count -gt 0) { continue }
        if ($file.Name -in @("auth.json", "config.toml", ".sync-manifest.json")) { continue }
        if ($file.Name -eq ".codex-private" -or $file.Name -match '(?i)\.bak(?:[-.].*)?$|\.backup(?:[-.].*)?$|~$') { continue }
        if ($file.Name -like "*.sqlite*" -or $file.Extension -in @(".pyc", ".pyo")) { continue }
        $destination = Join-Path $Target $relative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
    }
}

function Copy-DirectoryIfPresent {
    param(
        [string]$RelativePath,
        [string[]]$ExcludeDirectoryNames = @()
    )

    $source = Join-Path $CodexHome $RelativePath
    if (-not (Test-Path -LiteralPath $source -PathType Container)) { return $false }
    $target = Join-Path $srcRoot $RelativePath
    Copy-MaintainableDirectory -Source $source -Target $target -ExcludeDirectoryNames $ExcludeDirectoryNames
    return $true
}

function Copy-ActiveSkills {
    $source = Join-Path $CodexHome "skills"
    if (-not (Test-Path -LiteralPath $source -PathType Container)) { return 0 }
    $target = Join-Path $srcRoot "skills"
    New-Item -ItemType Directory -Force -Path $target | Out-Null

    $count = 0
    foreach ($dir in @(Get-ChildItem -LiteralPath $source -Directory -Force)) {
        if ($dir.Name -in @(".system", "codex-primary-runtime")) { continue }
        if (Test-Path -LiteralPath (Join-Path $dir.FullName ".codex-private") -PathType Leaf) { continue }
        Copy-MaintainableDirectory -Source $dir.FullName -Target (Join-Path $target $dir.Name)
        $count++
    }
    return $count
}

function Move-GeneratedEvalArtifactsOutOfSource {
    $relativePaths = @(
        "harness-evals\runs",
        "harness-evals\trace-evals\runs",
        "harness-evals\trace-evals\summaries"
    )
    $moved = New-Object System.Collections.Generic.List[string]
    $trash = ""
    foreach ($relative in $relativePaths) {
        $path = Join-Path $srcRoot $relative
        if (-not (Test-Path -LiteralPath $path)) { continue }
        if (-not $trash) {
            $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $trash = Join-Path $artifactsRoot "sync-excluded-eval-artifacts-$stamp"
            New-Item -ItemType Directory -Force -Path $trash | Out-Null
        }
        $target = Join-Path $trash $relative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Move-Item -LiteralPath $path -Destination $target
        $moved.Add($relative) | Out-Null
    }
    return $moved.ToArray()
}

New-Item -ItemType Directory -Force -Path $srcRoot | Out-Null
New-Item -ItemType Directory -Force -Path $artifactsRoot | Out-Null

if ($Refresh -and (Test-Path -LiteralPath $srcRoot)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backup = Join-Path $artifactsRoot "sync-refresh-$stamp"
    $refreshBackup = $backup
    New-Item -ItemType Directory -Force -Path $backup | Out-Null
    foreach ($item in @(Get-ChildItem -LiteralPath $srcRoot -Force)) {
        Move-Item -LiteralPath $item.FullName -Destination $backup
    }
}

$copiedFiles = New-Object System.Collections.Generic.List[string]
foreach ($file in @("AGENTS.md", "CODEX.md", "harness.capabilities.json", "harness.components.json", "hooks.json")) {
    if (Copy-FileIfPresent -RelativePath $file) { $copiedFiles.Add($file) | Out-Null }
}

$copiedDirs = New-Object System.Collections.Generic.List[string]
foreach ($dir in @("agents", "docs", "rules", "scripts", "templates")) {
    if (Copy-DirectoryIfPresent -RelativePath $dir) { $copiedDirs.Add($dir) | Out-Null }
}
if (Copy-DirectoryIfPresent -RelativePath "harness-evals" -ExcludeDirectoryNames @("runs")) {
    $copiedDirs.Add("harness-evals") | Out-Null
}

$skillCount = Copy-ActiveSkills
$excludedEvalArtifacts = Move-GeneratedEvalArtifactsOutOfSource

$sourceOnlyPreserved = New-Object System.Collections.Generic.List[string]
if ($refreshBackup) {
    foreach ($relative in @("automations")) {
        $sourceOnly = Join-Path $refreshBackup $relative
        if (Test-Path -LiteralPath $sourceOnly -PathType Container) {
            $target = Join-Path $srcRoot $relative
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
            Copy-Item -LiteralPath $sourceOnly -Destination $target -Recurse -Force
            $sourceOnlyPreserved.Add($relative) | Out-Null
        }
    }
}

$manifest = [ordered]@{
    schema = "codex-harness-source-sync-v1"
    synced_at = (Get-Date).ToString("o")
    direction = "runtime-to-source"
    codex_home = $CodexHome
    project_root = $ProjectRoot
    copied_files = $copiedFiles.ToArray()
    copied_directories = $copiedDirs.ToArray()
    copied_skill_count = $skillCount
    excluded_eval_artifacts = $excludedEvalArtifacts
    source_only_preserved = $sourceOnlyPreserved.ToArray()
    excluded = @(
        "config.toml",
        "auth.json",
        "*.sqlite*",
        "logs",
        "sessions",
        "cache",
        "plugins",
        "harness-health",
        "harness-changes",
        "runtime-generated automations except source templates",
        "harness-evals/runs",
        "harness-evals/trace-evals/runs",
        "harness-evals/trace-evals/summaries",
        "__pycache__",
        "*.pyc",
        "*.pyo",
        "skills.archived",
        "backup-*"
    )
}

$manifestDirectory = Join-Path $artifactsRoot "sync-manifests"
New-Item -ItemType Directory -Force -Path $manifestDirectory | Out-Null
$manifestPath = Join-Path $manifestDirectory ((Get-Date -Format "yyyyMMdd-HHmmssfff") + "-runtime-to-source.json")
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

[ordered]@{
    status = "success"
    summary = "Runtime source payload imported."
    codex_home = $CodexHome
    source_root = $srcRoot
    copied_files = $copiedFiles.ToArray()
    copied_directories = $copiedDirs.ToArray()
    copied_skill_count = $skillCount
    excluded_eval_artifacts = $excludedEvalArtifacts
    source_only_preserved = $sourceOnlyPreserved.ToArray()
    manifest = $manifestPath
} | ConvertTo-Json -Depth 8 -Compress
