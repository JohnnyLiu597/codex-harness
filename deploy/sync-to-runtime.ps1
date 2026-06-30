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

function ConvertTo-TomlBasicStringContent {
    param([string]$Value)

    return $Value.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
}

function ConvertTo-TomlBasicString {
    param([string]$Value)

    return '"' + (ConvertTo-TomlBasicStringContent -Value $Value) + '"'
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
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    foreach ($item in @(Get-ChildItem -LiteralPath $source -Force)) {
        if ($item.PSIsContainer -and $item.Name -in $ExcludeDirectoryNames) { continue }
        Copy-Item -LiteralPath $item.FullName -Destination $target -Recurse -Force
    }
    return $true
}

function Sync-HarnessAutomationTemplate {
    $template = Join-Path $srcRoot "automations\harness\automation.toml.template"
    if (-not (Test-Path -LiteralPath $template -PathType Leaf)) { return $false }

    $target = Join-Path $CodexHome "automations\harness\automation.toml"
    Assert-InCodexHome -Path $target
    if ($DryRun) { return $true }

    $nowMs = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
    $content = Get-Content -LiteralPath $template -Raw
    $content = $content.Replace("__CODEX_HOME_TOML_CONTENT__", (ConvertTo-TomlBasicStringContent -Value $CodexHome))
    $content = $content.Replace("__PROJECT_ROOT_TOML_STRING__", (ConvertTo-TomlBasicString -Value $ProjectRoot))
    $content = $content.Replace("__NOW_MS__", [string]$nowMs)

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Set-Content -LiteralPath $target -Value $content -Encoding UTF8
    return $true
}

$planned = @(
    "AGENTS.md",
    "CODEX.md",
    "harness.capabilities.json",
    "automations",
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
if (Sync-HarnessAutomationTemplate) {
    $copied.Add("automations\harness\automation.toml") | Out-Null
}

[ordered]@{
    status = if ($DryRun) { "dry-run" } else { "success" }
    summary = if ($DryRun) { "Runtime sync preview completed." } else { "Source payload synced to runtime." }
    codex_home = $CodexHome
    source_root = $srcRoot
    copied = $copied.ToArray()
    backup = $backupDir
} | ConvertTo-Json -Depth 8 -Compress
