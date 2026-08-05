param(
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
} else {
    $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
}

$syncToRuntime = Join-Path $ProjectRoot "deploy\sync-to-runtime.ps1"
$syncFromRuntime = Join-Path $ProjectRoot "deploy\sync-from-runtime.ps1"
$tmpRoot = Join-Path $env:TEMP ("codex-sync-boundary-test-" + [guid]::NewGuid().ToString("N"))
$privateDirectoryNames = @(
    '.sandbox', '.sandbox-bin', '.sandbox-secrets', '.tmp', 'tmp',
    'plugins', 'plugin', 'cache', 'caches', 'session', 'sessions',
    'archived_sessions', 'log', 'logs', 'hook-logs', 'browser',
    'browser-state', 'browser_state', 'computer-use', 'process_manager',
    'harness-health', 'harness-changes', 'harness-learning',
    'skills.archived', 'agents.archived', 'backups'
)
$privateFileNames = @('auth.json', 'config.toml', 'state.sqlite3')

function Write-Fixture {
    param([string]$Path, [string]$Value)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

function Assert-Present {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Expected path missing: $Path" }
}

function Assert-Absent {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) { throw "Excluded path crossed sync boundary: $Path" }
}

function Assert-Content {
    param([string]$Path, [string]$Expected)
    Assert-Present -Path $Path
    $actual = (Get-Content -LiteralPath $Path -Raw).Trim()
    if ($actual -ne $Expected) { throw "Unexpected content at ${Path}: $actual" }
}

New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
try {
    $sourceProject = Join-Path $tmpRoot "source-project"
    $runtimeTarget = Join-Path $tmpRoot "runtime-target"
    New-Item -ItemType Directory -Force -Path (Join-Path $sourceProject "src"), $runtimeTarget | Out-Null
    Write-Fixture -Path (Join-Path $sourceProject "src\rules\default.rules") -Value "allow"
    Write-Fixture -Path (Join-Path $sourceProject "src\rules\default.rules.bak-20260101") -Value "backup"
    Write-Fixture -Path (Join-Path $sourceProject "src\scripts\archived\legacy.ps1") -Value "legacy"
    Write-Fixture -Path (Join-Path $sourceProject "src\harness-learning\state.json") -Value "runtime state"
    Write-Fixture -Path (Join-Path $sourceProject "src\automations\harness\automation.toml.template") -Value "source template"
    Write-Fixture -Path (Join-Path $sourceProject "src\automations\weekly-private\automation.toml") -Value "source private task state"
    Write-Fixture -Path (Join-Path $runtimeTarget "automations\weekly-private\automation.toml") -Value "runtime private task state"
    foreach ($privateDir in $privateDirectoryNames) {
        Write-Fixture -Path (Join-Path $sourceProject "src\scripts\$privateDir\private.txt") -Value "private generated state"
    }
    foreach ($privateFile in $privateFileNames) {
        Write-Fixture -Path (Join-Path $sourceProject "src\scripts\nested\$privateFile") -Value "private generated file"
    }
    Write-Fixture -Path (Join-Path $sourceProject "src\skills\public-skill\SKILL.md") -Value "---`nname: public-skill`ndescription: Public fixture.`n---`n"
    Write-Fixture -Path (Join-Path $sourceProject "src\skills\private-skill\SKILL.md") -Value "source replacement"
    Write-Fixture -Path (Join-Path $runtimeTarget "skills\private-skill\SKILL.md") -Value "runtime private"
    Write-Fixture -Path (Join-Path $runtimeTarget "skills\private-skill\.codex-private") -Value "runtime-only"

    & $syncToRuntime -ProjectRoot $sourceProject -CodexHome $runtimeTarget -NoBackup | Out-Null
    Assert-Present -Path (Join-Path $runtimeTarget "rules\default.rules")
    Assert-Present -Path (Join-Path $runtimeTarget "skills\public-skill\SKILL.md")
    Assert-Absent -Path (Join-Path $runtimeTarget "rules\default.rules.bak-20260101")
    Assert-Absent -Path (Join-Path $runtimeTarget "scripts\archived\legacy.ps1")
    Assert-Absent -Path (Join-Path $runtimeTarget "harness-learning\state.json")
    Assert-Content -Path (Join-Path $runtimeTarget "automations\harness\automation.toml.template") -Expected "source template"
    Assert-Content -Path (Join-Path $runtimeTarget "automations\weekly-private\automation.toml") -Expected "runtime private task state"
    foreach ($privateDir in $privateDirectoryNames) {
        Assert-Absent -Path (Join-Path $runtimeTarget "scripts\$privateDir\private.txt")
    }
    foreach ($privateFile in $privateFileNames) {
        Assert-Absent -Path (Join-Path $runtimeTarget "scripts\nested\$privateFile")
    }
    Assert-Content -Path (Join-Path $runtimeTarget "skills\private-skill\SKILL.md") -Expected "runtime private"
    Assert-Present -Path (Join-Path $runtimeTarget "skills\private-skill\.codex-private")

    $runtimeSource = Join-Path $tmpRoot "runtime-source"
    $importProject = Join-Path $tmpRoot "import-project"
    New-Item -ItemType Directory -Force -Path $runtimeSource, $importProject | Out-Null
    Write-Fixture -Path (Join-Path $importProject "src\automations\harness\automation.toml.template") -Value "stale source template"
    Write-Fixture -Path (Join-Path $importProject "src\automations\weekly-private\automation.toml") -Value "stale runtime task state"
    Write-Fixture -Path (Join-Path $runtimeSource "rules\default.rules") -Value "allow"
    Write-Fixture -Path (Join-Path $runtimeSource "rules\default.rules.backup-20260101") -Value "backup"
    Write-Fixture -Path (Join-Path $runtimeSource "scripts\archived\legacy.ps1") -Value "legacy"
    Write-Fixture -Path (Join-Path $runtimeSource "harness-learning\state.json") -Value "runtime state"
    Write-Fixture -Path (Join-Path $runtimeSource "automations\harness\automation.toml.template") -Value "runtime template"
    Write-Fixture -Path (Join-Path $runtimeSource "automations\weekly-private\automation.toml") -Value "runtime task state"
    foreach ($privateDir in $privateDirectoryNames) {
        Write-Fixture -Path (Join-Path $runtimeSource "scripts\$privateDir\private.txt") -Value "private generated state"
    }
    foreach ($privateFile in $privateFileNames) {
        Write-Fixture -Path (Join-Path $runtimeSource "scripts\nested\$privateFile") -Value "private generated file"
    }
    Write-Fixture -Path (Join-Path $runtimeSource "skills\public-skill\SKILL.md") -Value "---`nname: public-skill`ndescription: Public fixture.`n---`n"
    Write-Fixture -Path (Join-Path $runtimeSource "skills\private-skill\SKILL.md") -Value "---`nname: private-skill`ndescription: Private fixture.`n---`n"
    Write-Fixture -Path (Join-Path $runtimeSource "skills\private-skill\.codex-private") -Value "runtime-only"

    & $syncFromRuntime -ProjectRoot $importProject -CodexHome $runtimeSource -Refresh | Out-Null
    Assert-Present -Path (Join-Path $importProject "src\rules\default.rules")
    Assert-Present -Path (Join-Path $importProject "src\skills\public-skill\SKILL.md")
    Assert-Absent -Path (Join-Path $importProject "src\rules\default.rules.backup-20260101")
    Assert-Absent -Path (Join-Path $importProject "src\scripts\archived\legacy.ps1")
    Assert-Absent -Path (Join-Path $importProject "src\harness-learning\state.json")
    Assert-Content -Path (Join-Path $importProject "src\automations\harness\automation.toml.template") -Expected "runtime template"
    Assert-Absent -Path (Join-Path $importProject "src\automations\weekly-private\automation.toml")
    foreach ($privateDir in $privateDirectoryNames) {
        Assert-Absent -Path (Join-Path $importProject "src\scripts\$privateDir\private.txt")
    }
    foreach ($privateFile in $privateFileNames) {
        Assert-Absent -Path (Join-Path $importProject "src\scripts\nested\$privateFile")
    }
    Assert-Absent -Path (Join-Path $importProject "src\skills\private-skill")

    [ordered]@{
        status = "success"
        summary = "Runtime/source sync boundaries preserve the public automation template and runtime-private tasks while excluding secrets, state databases, logs, sessions, plugins, caches, browser state, backups, sandbox and TEMP state, weekly learning state, and runtime-only private skills."
        cases = @("source-to-runtime", "runtime-to-source")
    } | ConvertTo-Json -Depth 5 -Compress
} finally {
    if (Test-Path -LiteralPath $tmpRoot) {
        Remove-Item -LiteralPath $tmpRoot -Recurse -Force
    }
}
