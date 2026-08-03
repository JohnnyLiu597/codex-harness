param(
    [string]$CodexHome = "$env:USERPROFILE\.codex",
    [string]$ProjectRoot = "",
    [switch]$DryRun,
    [switch]$NoBackup
)

$ErrorActionPreference = "Stop"

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
} else {
    $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
}

$CodexHome = (Resolve-Path -LiteralPath $CodexHome).Path
$srcRoot = Join-Path $ProjectRoot "src"
if (-not (Test-Path -LiteralPath $srcRoot -PathType Container)) {
    throw "Missing source payload: $srcRoot"
}

function Assert-InCodexHome {
    param([string]$Path)

    $full = if (Test-Path -LiteralPath $Path) {
        (Resolve-Path -LiteralPath $Path).Path
    } else {
        $Path
    }
    if (-not $full.StartsWith($CodexHome, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to write outside Codex home: $full"
    }
}

function Copy-FileToRuntime {
    param([string]$RelativePath)

    $source = Join-Path $srcRoot $RelativePath
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { return $false }
    $target = Join-Path $CodexHome $RelativePath
    Assert-InCodexHome -Path $target
    if ($DryRun) { return $true }
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
    $sourcePrefix = $Source.TrimEnd('\') + '\'
    $excludedDirectories = @($ExcludeDirectoryNames) + @("__pycache__")
    foreach ($file in @(Get-ChildItem -LiteralPath $Source -Recurse -Force -File)) {
        $relative = $file.FullName.Substring($sourcePrefix.Length)
        $segments = $relative -split '[\\/]'
        if (@($segments | Where-Object { $_ -in $excludedDirectories }).Count -gt 0) { continue }
        if ($file.Extension -in @(".pyc", ".pyo")) { continue }
        $destination = Join-Path $Target $relative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
    }
}

function Copy-DirectoryToRuntime {
    param(
        [string]$RelativePath,
        [string[]]$ExcludeDirectoryNames = @()
    )

    $source = Join-Path $srcRoot $RelativePath
    if (-not (Test-Path -LiteralPath $source -PathType Container)) { return $false }
    $target = Join-Path $CodexHome $RelativePath
    Assert-InCodexHome -Path $target
    if ($DryRun) { return $true }
    Copy-MaintainableDirectory -Source $source -Target $target -ExcludeDirectoryNames $ExcludeDirectoryNames
    return $true
}

$planned = @(
    "AGENTS.md",
    "CODEX.md",
    "harness.capabilities.json",
    "agents",
    "docs",
    "rules",
    "scripts",
    "templates",
    "harness-evals",
    "skills"
)

$backupDir = ""
if (-not $DryRun -and -not $NoBackup) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupDir = Join-Path $CodexHome "backup-$stamp-codex-harness-sync"
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    foreach ($relative in $planned) {
        $target = Join-Path $CodexHome $relative
        if (Test-Path -LiteralPath $target) {
            Copy-Item -LiteralPath $target -Destination (Join-Path $backupDir $relative) -Recurse -Force
        }
    }
}

$copied = New-Object System.Collections.Generic.List[string]
foreach ($file in @("AGENTS.md", "CODEX.md", "harness.capabilities.json")) {
    if (Copy-FileToRuntime -RelativePath $file) { $copied.Add($file) | Out-Null }
}
foreach ($dir in @("agents", "docs", "rules", "scripts", "templates", "skills")) {
    if (Copy-DirectoryToRuntime -RelativePath $dir) { $copied.Add($dir) | Out-Null }
}
if (Copy-DirectoryToRuntime -RelativePath "harness-evals" -ExcludeDirectoryNames @("runs")) {
    $copied.Add("harness-evals") | Out-Null
}

[ordered]@{
    status = if ($DryRun) { "dry-run" } else { "success" }
    summary = if ($DryRun) { "Runtime sync preview completed." } else { "Source payload synced to runtime." }
    codex_home = $CodexHome
    source_root = $srcRoot
    copied = $copied.ToArray()
    automation_template = "src\automations\harness\automation.toml.template"
    automation_note = "Register or update Codex App automations with the app automation_update tool; raw file sync alone does not make an automation visible in the app."
    backup = $backupDir
} | ConvertTo-Json -Depth 8 -Compress
