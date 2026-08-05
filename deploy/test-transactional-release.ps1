param(
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
} else {
    $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
}

$verifyRelease = Join-Path $ProjectRoot "deploy\verify-release.ps1"
$syncToRuntime = Join-Path $ProjectRoot "deploy\sync-to-runtime.ps1"
$tmpRoot = Join-Path $env:TEMP ("ctr-" + [guid]::NewGuid().ToString("N").Substring(0, 12))
$originalProbeRoot = $env:CODEX_RELEASE_TEST_PROBE_ROOT

function Write-Fixture {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Value
    )

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param(
        [AllowNull()]$Actual,
        [AllowNull()]$Expected,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ([string]$Actual -ne [string]$Expected) {
        throw "$Message Expected='$Expected' Actual='$Actual'"
    }
}

function Get-ContentValue {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Expected fixture file missing: $Path"
    }
    return (Get-Content -LiteralPath $Path -Raw).Trim()
}

function Get-ProbeCount {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 0 }
    return [int](Get-Content -LiteralPath $Path -Raw)
}

function Get-FileSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$RelativePaths
    )

    $snapshot = [ordered]@{}
    foreach ($relative in $RelativePaths) {
        $path = Join-Path $Root $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Snapshot fixture missing: $path"
        }
        $snapshot[$relative] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    return $snapshot
}

function Assert-Snapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Snapshot
    )

    foreach ($relative in $Snapshot.Keys) {
        $path = Join-Path $Root $relative
        Assert-True -Condition (Test-Path -LiteralPath $path -PathType Leaf) -Message "Runtime state was removed: $relative"
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-Equal -Actual $hash -Expected $Snapshot[$relative] -Message "Runtime state changed: $relative"
    }
}

function Write-SuccessStub {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Status = "success",
        [string]$Summary = "fixture step passed"
    )

    $body = @"
param(
    [string]`$ProjectRoot = "",
    [string]`$CodexHome = ""
)
[ordered]@{
    status = "$Status"
    summary = "$Summary"
    read_only = `$true
} | ConvertTo-Json -Compress
"@
    Write-Fixture -Path $Path -Value $body
}

function New-ReleaseFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$SourceRule = "source-v2"
    )

    $root = Join-Path $tmpRoot $Name
    $project = Join-Path $root "project"
    $runtime = Join-Path $root "runtime"
    $probe = Join-Path $root "probe"
    New-Item -ItemType Directory -Force -Path $project, $runtime, $probe | Out-Null

    New-Item -ItemType Directory -Force -Path (Join-Path $project "deploy") | Out-Null
    Copy-Item -LiteralPath $syncToRuntime -Destination (Join-Path $project "deploy\sync-to-runtime.ps1") -Force
    Write-SuccessStub -Path (Join-Path $project "deploy\verify-package.ps1")
    Write-SuccessStub -Path (Join-Path $project "deploy\test-sync-boundaries.ps1")
    Write-SuccessStub -Path (Join-Path $project "src\harness-evals\test-project-harness-optimizer.ps1")
    Write-SuccessStub -Path (Join-Path $project "src\scripts\audit-context-budget.ps1") -Status "passed"
    Write-SuccessStub -Path (Join-Path $project "src\scripts\audit-harness-components.ps1") -Status "passed"
    Write-SuccessStub -Path (Join-Path $project "src\scripts\test-codex-workflow-core.ps1")
    Write-SuccessStub -Path (Join-Path $project "src\harness-evals\test-verification-envelope.ps1")

    $verifier = @'
param(
    [string]$CodexHome = "$env:USERPROFILE\.codex"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $CodexHome).Path
$probeRoot = $env:CODEX_RELEASE_TEST_PROBE_ROOT
$isStage = $env:CODEX_RELEASE_STAGE -eq "1"

function Get-RelativeFiles {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolved = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path).TrimEnd('\')
    return @(Get-ChildItem -LiteralPath $resolved -Recurse -Force -File | ForEach-Object {
        $_.FullName.Substring($resolved.Length).TrimStart('\')
    } | Sort-Object)
}

function Assert-MaintainableOnly {
    param([Parameter(Mandatory = $true)][string]$Path)

    $files = Get-RelativeFiles -Path $Path
    $forbidden = @($files | Where-Object {
        $segments = $_ -split '[\\/]'
        $name = $segments[-1]
        $directorySegments = @($segments | Select-Object -First ([math]::Max(0, $segments.Count - 1)))
        ($name -in @('auth.json', 'config.toml', '.sync-manifest.json')) -or
        ($name -like '*.sqlite*') -or
        ($name -match '(?i)\.(db|db3|sdb|db-wal|db-shm)$') -or
        (@($directorySegments | Where-Object {
            $_ -in @(
                'plugins', 'plugin', 'cache', 'caches', 'session', 'sessions', 'archived_sessions',
                'log', 'logs', 'hook-logs', 'browser', 'browser-state', 'browser_state',
                'computer-use', 'process_manager', 'harness-health', 'harness-changes',
                'harness-learning', 'skills.archived', 'agents.archived', 'backups',
                '.sandbox', '.sandbox-bin', '.sandbox-secrets', '.tmp', 'tmp'
            )
        }).Count -gt 0)
    })
    if ($forbidden.Count -gt 0) {
        throw "Forbidden state entered staging: $($forbidden -join ', ')"
    }
    return $files
}

function Increment-ProbeCount {
    param([Parameter(Mandatory = $true)][string]$Name)

    $countPath = Join-Path $probeRoot $Name
    $count = if (Test-Path -LiteralPath $countPath) { [int](Get-Content -LiteralPath $countPath -Raw) } else { 0 }
    Set-Content -LiteralPath $countPath -Value ($count + 1) -Encoding ASCII
}

if ($isStage) {
    $stageRoot = $env:CODEX_RELEASE_STAGING_ROOT
    if ([string]::IsNullOrWhiteSpace($stageRoot) -or -not (Test-Path -LiteralPath $stageRoot -PathType Container)) {
        throw 'Pure staging root was not supplied to global verification.'
    }
    $files = Assert-MaintainableOnly -Path $stageRoot
    Increment-ProbeCount -Name 'stage-global-verify-count.txt'
    $snapshot = [ordered]@{
        root_name = Split-Path -Leaf $stageRoot
        files = $files
    }
    $snapshot | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $probeRoot 'stage-snapshot.json') -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $probeRoot 'stage-verified.marker') -Value 'verified' -Encoding ASCII
} else {
    if (-not (Test-Path -LiteralPath (Join-Path $probeRoot 'stage-verified.marker') -PathType Leaf)) {
        throw 'Runtime verification ran before staging verification.'
    }
    Increment-ProbeCount -Name 'runtime-global-verify-count.txt'
    $rule = (Get-Content -LiteralPath (Join-Path $root 'rules\default.rules') -Raw).Trim()
    if ($rule -eq 'force-post-install-failure') {
        throw 'Forced post-install verification failure.'
    }
}

[ordered]@{
    status = 'success'
    summary = if ($isStage) { 'fixture staging verified' } else { 'fixture runtime verified' }
} | ConvertTo-Json -Compress
'@
    Write-Fixture -Path (Join-Path $project "src\scripts\verify-global-harness.ps1") -Value $verifier

    $evalRunner = @'
param(
    [string]$CodexHome = "$env:USERPROFILE\.codex"
)

$ErrorActionPreference = "Stop"
if ($env:CODEX_RELEASE_STAGE -ne '1') {
    throw 'Deterministic evals must run only in staging.'
}
if (Test-Path -LiteralPath (Join-Path $CodexHome 'config.toml')) {
    throw 'Deterministic evals received a staging root containing config.toml.'
}
$countPath = Join-Path $env:CODEX_RELEASE_TEST_PROBE_ROOT 'eval-count.txt'
$count = if (Test-Path -LiteralPath $countPath) { [int](Get-Content -LiteralPath $countPath -Raw) } else { 0 }
Set-Content -LiteralPath $countPath -Value ($count + 1) -Encoding ASCII
foreach ($relative in @(
    'harness-health\skill-surface\fixture\summary.json',
    'harness-evals\runs\fixture\evals.json',
    'harness-evals\trace-evals\runs\fixture\evals.json',
    'harness-evals\trace-evals\summaries\fixture.json'
)) {
    $path = Join-Path $CodexHome $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
    Set-Content -LiteralPath $path -Value '{}' -Encoding ASCII
}
[ordered]@{
    status = 'success'
    summary = 'fixture deterministic evals passed'
} | ConvertTo-Json -Compress
'@
    Write-Fixture -Path (Join-Path $project "src\harness-evals\run-harness-evals.ps1") -Value $evalRunner

    Write-Fixture -Path (Join-Path $project "src\rules\default.rules") -Value $SourceRule
    Write-Fixture -Path (Join-Path $project "src\AGENTS.md") -Value "fixture agents"
    Write-Fixture -Path (Join-Path $project "src\automations\harness\automation.toml.template") -Value "fixture public automation"
    Write-Fixture -Path (Join-Path $project "src\automations\weekly-private\automation.toml") -Value "source private automation"
    Write-Fixture -Path (Join-Path $project "src\skills\public-skill\SKILL.md") -Value "fixture public skill"
    Write-Fixture -Path (Join-Path $project "src\scripts\nested\auth.json") -Value "source auth secret"
    Write-Fixture -Path (Join-Path $project "src\scripts\nested\config.toml") -Value "source config secret"
    Write-Fixture -Path (Join-Path $project "src\scripts\nested\state.sqlite3") -Value "source sqlite state"
    Write-Fixture -Path (Join-Path $project "src\scripts\nested\runtime.db") -Value "source db state"
    Write-Fixture -Path (Join-Path $project "src\scripts\sessions\private.json") -Value "source session state"
    Write-Fixture -Path (Join-Path $project "src\scripts\logs\private.log") -Value "source log state"
    Write-Fixture -Path (Join-Path $project "src\scripts\plugins\private.bin") -Value "source plugin state"
    Write-Fixture -Path (Join-Path $project "src\scripts\cache\private.bin") -Value "source cache state"
    Write-Fixture -Path (Join-Path $project "src\scripts\browser-state\private.json") -Value "source browser state"

    $oldVerifier = @'
param([string]$CodexHome = "$env:USERPROFILE\.codex")
[ordered]@{ status = 'success'; summary = 'restored runtime verified' } | ConvertTo-Json -Compress
'@
    Write-Fixture -Path (Join-Path $runtime "scripts\verify-global-harness.ps1") -Value $oldVerifier
    Write-Fixture -Path (Join-Path $runtime "rules\default.rules") -Value "runtime-v1"
    Write-Fixture -Path (Join-Path $runtime "config.toml") -Value "runtime-config-secret"
    Write-Fixture -Path (Join-Path $runtime "auth.json") -Value "runtime-auth-secret"
    Write-Fixture -Path (Join-Path $runtime "state.sqlite3") -Value "runtime-database-secret"
    Write-Fixture -Path (Join-Path $runtime "sessions\session.json") -Value "runtime-session-secret"
    Write-Fixture -Path (Join-Path $runtime "logs\runtime.log") -Value "runtime-log-secret"
    Write-Fixture -Path (Join-Path $runtime "plugins\plugin.bin") -Value "runtime-plugin-secret"
    Write-Fixture -Path (Join-Path $runtime "cache\cache.bin") -Value "runtime-cache-secret"
    Write-Fixture -Path (Join-Path $runtime "browser-state\state.json") -Value "runtime-browser-secret"
    Write-Fixture -Path (Join-Path $runtime "automations\weekly-private\automation.toml") -Value "runtime-private-automation"
    Write-Fixture -Path (Join-Path $runtime "skills\private-skill\SKILL.md") -Value "runtime-private-skill"
    Write-Fixture -Path (Join-Path $runtime "skills\private-skill\.codex-private") -Value "runtime-only"
    Write-Fixture -Path (Join-Path $runtime "scripts\cache\private.bin") -Value "nested-runtime-cache"
    Write-Fixture -Path (Join-Path $runtime "scripts\nested\runtime.db") -Value "nested-runtime-db"

    return [pscustomobject]@{
        Root = $root
        Project = $project
        Runtime = $runtime
        Probe = $probe
    }
}

function Invoke-ReleaseFixture {
    param(
        [Parameter(Mandatory = $true)]$Fixture,
        [Parameter(Mandatory = $true)][string]$Level,
        [switch]$InstallRuntime,
        [int]$StepTimeoutSeconds = 30
    )

    $env:CODEX_RELEASE_TEST_PROBE_ROOT = $Fixture.Probe
    $arguments = @(
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy", "Bypass",
        "-File", $verifyRelease,
        "-ProjectRoot", $Fixture.Project,
        "-CodexHome", $Fixture.Runtime,
        "-Level", $Level,
        "-SkipGitChecks",
        "-StepTimeoutSeconds", [string]$StepTimeoutSeconds
    )
    if ($InstallRuntime) { $arguments += "-InstallRuntime" }

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $raw = @(& powershell.exe @arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    $result = $null
    foreach ($line in @($raw | ForEach-Object { [string]$_ })) {
        $trimmed = $line.Trim()
        if (-not $trimmed.StartsWith("{")) { continue }
        try {
            $candidate = $trimmed | ConvertFrom-Json
            if ($candidate.PSObject.Properties.Name -contains "release_id") {
                $result = $candidate
            }
        } catch { }
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Result = $result
        Raw = ($raw -join "`n")
    }
}

function Get-ReleaseManifest {
    param([Parameter(Mandatory = $true)]$Invocation)

    if (-not $Invocation.Result) {
        throw "Release result JSON missing. Output: $($Invocation.Raw)"
    }
    $manifestPath = [string]$Invocation.Result.manifest
    Assert-True -Condition (Test-Path -LiteralPath $manifestPath -PathType Leaf) -Message "Release manifest missing: $manifestPath"
    return Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
}

function Assert-ManifestSanitized {
    param(
        [Parameter(Mandatory = $true)]$Invocation,
        [Parameter(Mandatory = $true)]$Fixture
    )

    $manifestPath = [string]$Invocation.Result.manifest
    $raw = Get-Content -LiteralPath $manifestPath -Raw
    foreach ($secret in @(
        "runtime-config-secret",
        "runtime-auth-secret",
        "runtime-database-secret",
        "runtime-session-secret",
        "runtime-log-secret",
        "runtime-plugin-secret",
        "runtime-cache-secret",
        "runtime-browser-secret",
        "source auth secret",
        "source config secret",
        "source sqlite state",
        "source db state",
        "source session state",
        "source log state",
        "source plugin state",
        "source cache state",
        "source browser state"
    )) {
        Assert-True -Condition (-not $raw.Contains($secret)) -Message "Release manifest leaked runtime state: $secret"
    }
    Assert-True -Condition (-not $raw.Contains($Fixture.Runtime)) -Message "Release manifest persisted the real runtime path."
    Assert-True -Condition (-not $raw.Contains($Fixture.Project)) -Message "Release manifest persisted the real project path."
}

function Assert-NoForbiddenBackupState {
    param([Parameter(Mandatory = $true)][string]$ManifestPath)

    $releaseRoot = Split-Path -Parent $ManifestPath
    $prefix = $releaseRoot.TrimEnd('\') + '\'
    $forbidden = @(Get-ChildItem -LiteralPath $releaseRoot -Recurse -Force -File | Where-Object {
        $relative = $_.FullName.Substring($prefix.Length)
        $segments = $relative -split '[\\/]'
        $name = $segments[-1]
        $directories = @($segments | Select-Object -First ([math]::Max(0, $segments.Count - 1)))
        ($name -in @('auth.json', 'config.toml')) -or
        ($name -like '*.sqlite*') -or
        ($name -match '(?i)\.(db|db-wal|db-shm)$') -or
        (@($directories | Where-Object {
            $_ -in @('plugins', 'plugin', 'cache', 'caches', 'session', 'sessions', 'archived_sessions', 'log', 'logs', 'hook-logs', 'browser', 'browser-state', 'browser_state')
        }).Count -gt 0)
    })
    Assert-Equal -Actual $forbidden.Count -Expected 0 -Message "Forbidden runtime state entered release backup artifacts."

    foreach ($file in @(Get-ChildItem -LiteralPath $releaseRoot -Recurse -Force -File)) {
        $raw = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
        if ($null -eq $raw) { continue }
        foreach ($secret in @(
            'runtime-config-secret', 'runtime-auth-secret', 'runtime-database-secret',
            'runtime-session-secret', 'runtime-log-secret', 'runtime-plugin-secret',
            'runtime-cache-secret', 'runtime-browser-secret', 'nested-runtime-cache',
            'nested-runtime-db'
        )) {
            Assert-True -Condition (-not $raw.Contains($secret)) -Message "Release artifacts leaked runtime-only content: $secret"
        }
    }
}

$cases = New-Object System.Collections.Generic.List[string]
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
try {
    $stagingFixture = New-ReleaseFixture -Name "full-staging"
    $stagingRun = Invoke-ReleaseFixture -Fixture $stagingFixture -Level "Full"
    Assert-Equal -Actual $stagingRun.ExitCode -Expected 0 -Message "Full staging-only release failed. $($stagingRun.Raw)"
    $stagingManifest = Get-ReleaseManifest -Invocation $stagingRun
    Assert-Equal -Actual $stagingRun.Result.installed_runtime -Expected $false -Message "Full implicitly installed the runtime."
    Assert-Equal -Actual (Get-ContentValue -Path (Join-Path $stagingFixture.Runtime "rules\default.rules")) -Expected "runtime-v1" -Message "Staging-only Full mutated the runtime."
    Assert-Equal -Actual (Get-ProbeCount -Path (Join-Path $stagingFixture.Probe "stage-global-verify-count.txt")) -Expected 1 -Message "Global verification did not run exactly once in staging."
    Assert-Equal -Actual (Get-ProbeCount -Path (Join-Path $stagingFixture.Probe "eval-count.txt")) -Expected 1 -Message "Deterministic evals did not run exactly once in staging."
    Assert-Equal -Actual (Get-ProbeCount -Path (Join-Path $stagingFixture.Probe "runtime-global-verify-count.txt")) -Expected 0 -Message "Staging-only Full verified or mutated the real runtime."
    Assert-Equal -Actual $stagingManifest.staging.status -Expected "verified" -Message "Manifest did not record verified staging."
    Assert-Equal -Actual $stagingManifest.staging.global_verify_runs -Expected 1 -Message "Manifest staging global verify count is incorrect."
    Assert-Equal -Actual $stagingManifest.staging.deterministic_eval_runs -Expected 1 -Message "Manifest staging eval count is incorrect."
    $stagingStepNames = [string[]]@($stagingManifest.steps | ForEach-Object { [string]$_.name })
    foreach ($duplicateBehaviorStep in @(
        "source-optimizer-self-test",
        "source-context-budget",
        "source-component-registry",
        "source-workflow-core",
        "source-verification-gate",
        "source-verification-envelope"
    )) {
        Assert-True -Condition ($stagingStepNames -notcontains $duplicateBehaviorStep) -Message "Full release duplicated behavior verification outside the staging eval runner: $duplicateBehaviorStep"
    }
    Assert-True -Condition ($stagingStepNames -contains "staging-generated-evidence-cleanup") -Message "Full release did not clean staging eval evidence before its final boundary check."
    Assert-Equal -Actual $stagingManifest.install.status -Expected "not-requested" -Message "Manifest recorded an unexpected install."
    Assert-True -Condition ([bool]$stagingManifest.source.fingerprint_sha256) -Message "Manifest source fingerprint is missing."
    $stageSnapshot = Get-Content -LiteralPath (Join-Path $stagingFixture.Probe "stage-snapshot.json") -Raw | ConvertFrom-Json
    Assert-True -Condition (@($stageSnapshot.files | Where-Object { $_ -match '(^|[\\/])config\.toml$' }).Count -eq 0) -Message "Pure staging included config.toml."
    Assert-ManifestSanitized -Invocation $stagingRun -Fixture $stagingFixture
    $cases.Add("full-staging-without-install") | Out-Null

    $installFixture = New-ReleaseFixture -Name "transactional-install"
    $statePaths = @(
        "config.toml", "auth.json", "state.sqlite3", "sessions\session.json",
        "logs\runtime.log", "plugins\plugin.bin", "cache\cache.bin",
        "browser-state\state.json", "automations\weekly-private\automation.toml",
        "skills\private-skill\SKILL.md", "skills\private-skill\.codex-private",
        "scripts\cache\private.bin", "scripts\nested\runtime.db"
    )
    $stateBefore = Get-FileSnapshot -Root $installFixture.Runtime -RelativePaths $statePaths
    $installRun = Invoke-ReleaseFixture -Fixture $installFixture -Level "Full" -InstallRuntime
    Assert-Equal -Actual $installRun.ExitCode -Expected 0 -Message "Transactional Full install failed. $($installRun.Raw)"
    $installManifest = Get-ReleaseManifest -Invocation $installRun
    Assert-Equal -Actual (Get-ContentValue -Path (Join-Path $installFixture.Runtime "rules\default.rules")) -Expected "source-v2" -Message "Successful install did not update maintainable runtime state."
    Assert-Snapshot -Root $installFixture.Runtime -Snapshot $stateBefore
    Assert-Equal -Actual (Get-ProbeCount -Path (Join-Path $installFixture.Probe "stage-global-verify-count.txt")) -Expected 1 -Message "Install path did not globally verify staging exactly once."
    Assert-Equal -Actual (Get-ProbeCount -Path (Join-Path $installFixture.Probe "eval-count.txt")) -Expected 1 -Message "Install path ran deterministic evals outside staging or more than once."
    Assert-Equal -Actual (Get-ProbeCount -Path (Join-Path $installFixture.Probe "runtime-global-verify-count.txt")) -Expected 1 -Message "Install path did not globally verify runtime exactly once."
    Assert-Equal -Actual $installManifest.install.status -Expected "verified" -Message "Manifest did not record verified install."
    Assert-Equal -Actual $installManifest.install.global_verify_runs -Expected 1 -Message "Manifest runtime global verify count is incorrect."
    Assert-Equal -Actual $installManifest.install.canary_runs -Expected 1 -Message "Manifest runtime canary count is incorrect."
    Assert-Equal -Actual $installManifest.install.rollback.status -Expected "not-needed" -Message "Successful install unexpectedly rolled back."
    $stepNames = @($installManifest.steps | ForEach-Object { $_.name })
    Assert-True -Condition ($stepNames.IndexOf("staging-harness-evals") -lt $stepNames.IndexOf("runtime-sync-install")) -Message "Runtime mutation occurred before staging evals."
    Assert-True -Condition ($stepNames.IndexOf("runtime-global-verify") -lt $stepNames.IndexOf("runtime-install-canary")) -Message "Runtime canary did not follow global verification."
    Assert-NoForbiddenBackupState -ManifestPath ([string]$installRun.Result.manifest)
    Assert-ManifestSanitized -Invocation $installRun -Fixture $installFixture
    $cases.Add("transactional-install-and-runtime-state-preservation") | Out-Null

    $rollbackFixture = New-ReleaseFixture -Name "forced-rollback" -SourceRule "force-post-install-failure"
    $rollbackStateBefore = Get-FileSnapshot -Root $rollbackFixture.Runtime -RelativePaths $statePaths
    $oldVerifierHash = (Get-FileHash -LiteralPath (Join-Path $rollbackFixture.Runtime "scripts\verify-global-harness.ps1") -Algorithm SHA256).Hash
    $rollbackRun = Invoke-ReleaseFixture -Fixture $rollbackFixture -Level "Full" -InstallRuntime
    Assert-True -Condition ($rollbackRun.ExitCode -ne 0) -Message "Forced post-install failure unexpectedly succeeded."
    $rollbackManifest = Get-ReleaseManifest -Invocation $rollbackRun
    Assert-Equal -Actual $rollbackManifest.status -Expected "failed" -Message "Failed release manifest status is incorrect."
    Assert-Equal -Actual $rollbackManifest.install.rollback.status -Expected "rolled-back" -Message "Post-install failure did not roll back."
    Assert-Equal -Actual (Get-ContentValue -Path (Join-Path $rollbackFixture.Runtime "rules\default.rules")) -Expected "runtime-v1" -Message "Rollback did not restore the prior rule."
    $restoredVerifierHash = (Get-FileHash -LiteralPath (Join-Path $rollbackFixture.Runtime "scripts\verify-global-harness.ps1") -Algorithm SHA256).Hash
    Assert-Equal -Actual $restoredVerifierHash -Expected $oldVerifierHash -Message "Rollback did not restore the prior verifier."
    Assert-Snapshot -Root $rollbackFixture.Runtime -Snapshot $rollbackStateBefore
    Assert-Equal -Actual (Get-ProbeCount -Path (Join-Path $rollbackFixture.Probe "stage-global-verify-count.txt")) -Expected 1 -Message "Rollback path did not globally verify staging exactly once."
    Assert-Equal -Actual (Get-ProbeCount -Path (Join-Path $rollbackFixture.Probe "eval-count.txt")) -Expected 1 -Message "Rollback path reran deterministic evals."
    Assert-Equal -Actual (Get-ProbeCount -Path (Join-Path $rollbackFixture.Probe "runtime-global-verify-count.txt")) -Expected 1 -Message "Rollback path did not run the failing runtime verifier exactly once."
    Assert-NoForbiddenBackupState -ManifestPath ([string]$rollbackRun.Result.manifest)
    Assert-ManifestSanitized -Invocation $rollbackRun -Fixture $rollbackFixture
    $cases.Add("forced-failure-rollback") | Out-Null

    $timeoutFixture = New-ReleaseFixture -Name "timeout-cleanup"
    $timeoutStub = @'
param([string]$ProjectRoot = '')
$child = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 60') -WindowStyle Hidden -PassThru
Set-Content -LiteralPath (Join-Path $env:CODEX_RELEASE_TEST_PROBE_ROOT 'timeout-child.pid') -Value $child.Id -Encoding ASCII
Start-Sleep -Seconds 60
[ordered]@{ status = 'success'; summary = 'unexpected timeout success' } | ConvertTo-Json -Compress
'@
    Write-Fixture -Path (Join-Path $timeoutFixture.Project "deploy\verify-package.ps1") -Value $timeoutStub
    $timeoutRun = Invoke-ReleaseFixture -Fixture $timeoutFixture -Level "Fast" -StepTimeoutSeconds 2
    Assert-True -Condition ($timeoutRun.ExitCode -ne 0) -Message "Timed-out release unexpectedly succeeded."
    $timeoutManifest = Get-ReleaseManifest -Invocation $timeoutRun
    $timeoutStep = @($timeoutManifest.steps | Where-Object { $_.name -eq "package-public-readiness" })[0]
    Assert-Equal -Actual $timeoutStep.status -Expected "failed" -Message "Timed-out step was not marked failed."
    Assert-Equal -Actual $timeoutStep.timed_out -Expected $true -Message "Timed-out step did not record timeout status."
    Start-Sleep -Milliseconds 750
    $childPid = [int](Get-ContentValue -Path (Join-Path $timeoutFixture.Probe "timeout-child.pid"))
    Assert-True -Condition (-not (Get-Process -Id $childPid -ErrorAction SilentlyContinue)) -Message "Timed-out step left a child process running."
    $cases.Add("bounded-timeout-process-tree-cleanup") | Out-Null

    [ordered]@{
        status = "success"
        summary = "Transactional release staging, install, rollback, state preservation, forbidden-state exclusion, manifest sanitization, and timeout cleanup passed."
        cases = $cases.ToArray()
    } | ConvertTo-Json -Depth 6 -Compress
} finally {
    $env:CODEX_RELEASE_TEST_PROBE_ROOT = $originalProbeRoot
    if ($env:CODEX_RELEASE_TEST_KEEP_FIXTURES -eq '1') {
        Write-Warning "Transactional release fixtures retained at: $tmpRoot"
    } elseif (Test-Path -LiteralPath $tmpRoot) {
        $resolvedTmp = (Resolve-Path -LiteralPath $tmpRoot).Path
        $resolvedTempRoot = (Resolve-Path -LiteralPath $env:TEMP).Path.TrimEnd('\') + '\'
        if ($resolvedTmp.StartsWith($resolvedTempRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
            (Split-Path -Leaf $resolvedTmp).StartsWith("ctr-")) {
            Remove-Item -LiteralPath $resolvedTmp -Recurse -Force
        }
    }
}
