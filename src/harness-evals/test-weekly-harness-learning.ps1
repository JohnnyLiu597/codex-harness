param(
    [string]$CodexHome = "$env:USERPROFILE\.codex"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $CodexHome).Path
$scriptPath = Join-Path $root 'scripts\invoke-weekly-harness-learning.ps1'
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw "Weekly harness learning script missing: $scriptPath"
}

$tmpRoot = Join-Path $env:TEMP ("codex-weekly-learning-test-" + (Get-Date -Format 'yyyyMMddHHmmssfff'))
foreach ($relative in @(
    'scripts',
    'docs',
    'skills\sample\references',
    'harness-evals\cases\weekly-learning',
    'automations\harness'
)) {
    New-Item -ItemType Directory -Force -Path (Join-Path $tmpRoot $relative) | Out-Null
}
Copy-Item -LiteralPath $scriptPath -Destination (Join-Path $tmpRoot 'scripts\invoke-weekly-harness-learning.ps1')
Set-Content -LiteralPath (Join-Path $tmpRoot 'docs\weekly-learning.md') -Value '# Weekly Harness Learning' -Encoding UTF8

$inputPath = ''
$inputFixture = [ordered]@{
    schema = 'codex-weekly-harness-learning-input-v1'
    tasks = @(
        [ordered]@{
            source_ref = 'thread-private-id'
            updated_at = (Get-Date).ToString('o')
            findings = @(
                [ordered]@{
                    category = 'test-gap'
                    summary = 'Contact owner@example.com, open https://private.example/path?token=do-not-store, and use token=do-not-store before adding a regression case.'
                    confidence = 0.9
                    frequency = 'repeated'
                    route = 'eval'
                    evidence_ref = 'thread-private-id|turn-7'
                }
            )
        }
    )
    research = @(
        [ordered]@{
            title = 'Official Codex guidance'
            url = 'https://developers.openai.com/codex?token=secret#section'
            source_type = 'official'
            concepts = @('Use bounded verification evidence.')
        },
        [ordered]@{
            title = 'Private host must be rejected'
            url = 'https://intranet.local/private/path?token=secret'
            source_type = 'official'
            concepts = @('This must not persist.')
        }
    )
    proposals = @(
        [ordered]@{
            id = 'hook-review'
            risk = 'high'
            summary = 'Review a lifecycle policy change.'
            rationale = 'Hooks remain proposal-only.'
            paths = @('hooks.json')
        }
    )
}

function Register-InputPath {
    param(
        [string]$RunId,
        [string]$Path
    )

    $activeRunPath = Join-Path $tmpRoot 'harness-learning\active-run.json'
    if (-not (Test-Path -LiteralPath $activeRunPath -PathType Leaf)) {
        throw 'Cannot register a weekly input without an active run.'
    }
    $activeRun = Get-Content -LiteralPath $activeRunPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$activeRun.run_id -ne $RunId) {
        throw "Active weekly run does not match input registration: $RunId"
    }
    $activeRun | Add-Member -NotePropertyName input_path -NotePropertyValue ([System.IO.Path]::GetFullPath($Path)) -Force
    $activeRun | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $activeRunPath -Encoding UTF8
}

function Write-InputFixture {
    param([string]$RunId)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($inputFixture | ConvertTo-Json -Depth 10))
    $offset = 0
    $chunkIndex = 0
    $result = $null
    while ($offset -lt $bytes.Length) {
        $count = [math]::Min(257, $bytes.Length - $offset)
        $chunk = New-Object byte[] $count
        [Array]::Copy($bytes, $offset, $chunk, 0, $count)
        $parameters = @{
            Mode = 'WriteInput'
            CodexHome = $tmpRoot
            RunId = $RunId
            ChunkIndex = $chunkIndex
            InputChunkBase64 = [Convert]::ToBase64String($chunk)
        }
        if (($offset + $count) -eq $bytes.Length) { $parameters.FinalChunk = $true }
        $result = (& (Join-Path $tmpRoot 'scripts\invoke-weekly-harness-learning.ps1') @parameters) | ConvertFrom-Json
        if ($result.status -ne 'success' -or [int]$result.accepted_chunk_index -ne $chunkIndex) {
            throw "WriteInput did not accept chunk $chunkIndex."
        }
        $offset += $count
        $chunkIndex += 1
    }
    if (-not [bool]$result.final -or [string]::IsNullOrWhiteSpace([string]$result.input_path)) {
        throw 'WriteInput did not finalize and register the sanitized input.'
    }
    return [string]$result.input_path
}

$startRaw = & (Join-Path $tmpRoot 'scripts\invoke-weekly-harness-learning.ps1') -Mode Start -CodexHome $tmpRoot -SkipHealth
$start = $startRaw | ConvertFrom-Json
if ($start.status -ne 'success' -or [string]::IsNullOrWhiteSpace($start.run_id)) {
    throw 'Weekly learning Start did not return a usable run id.'
}
if ([string]::IsNullOrWhiteSpace($start.temporary_input_prefix) -or
    -not ([string]$start.temporary_input_prefix).StartsWith([System.IO.Path]::GetFullPath($env:TEMP), [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Weekly learning Start did not return a canonical TEMP input prefix.'
}
if ([int]$start.input_chunk_max_bytes -ne 8192 -or [int]$start.input_chunk_max_count -ne 64) {
    throw 'Weekly learning Start did not advertise the bounded WriteInput contract.'
}

$inputPath = Write-InputFixture -RunId $start.run_id
$completeRaw = & (Join-Path $tmpRoot 'scripts\invoke-weekly-harness-learning.ps1') -Mode Complete -CodexHome $tmpRoot -RunId $start.run_id -InputPath $inputPath
$complete = $completeRaw | ConvertFrom-Json
if ($complete.status -ne 'success' -or -not $complete.state_written) {
    throw 'Weekly learning Complete did not write successful state.'
}
if (Test-Path -LiteralPath $inputPath) {
    throw 'Weekly learning retained the temporary raw input after ingestion.'
}

$reportPath = @($complete.artifacts)[0]
$reportRaw = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8
if ($reportRaw -match 'Contact|owner@example\.com|do-not-store|thread-private-id|turn-7|private\.example|intranet\.local|Official Codex guidance|Private host must be rejected|Use bounded verification evidence|This must not persist|Hooks remain proposal-only|\?token=') {
    throw 'Weekly learning report retained raw identifiers or sensitive values.'
}
foreach ($required in @('"category":  "test-gap"', '"url":  "https://developers.openai.com/codex"', '"summary_hash"', '"rejected_research":  1', '"temporary_input_deleted":  true')) {
    if ($reportRaw -notmatch [regex]::Escape($required)) {
        throw "Weekly learning report is missing expected sanitization evidence: $required"
    }
}

$secondStart = (& (Join-Path $tmpRoot 'scripts\invoke-weekly-harness-learning.ps1') -Mode Start -CodexHome $tmpRoot -SkipHealth) | ConvertFrom-Json
$inputPath = Write-InputFixture -RunId $secondStart.run_id
$secondComplete = (& (Join-Path $tmpRoot 'scripts\invoke-weekly-harness-learning.ps1') -Mode Complete -CodexHome $tmpRoot -RunId $secondStart.run_id -InputPath $inputPath) | ConvertFrom-Json
$secondReport = Get-Content -LiteralPath @($secondComplete.artifacts)[0] -Raw -Encoding UTF8 | ConvertFrom-Json
if ($secondReport.intake.duplicate_tasks -ne 1 -or $secondReport.intake.new_findings -ne 0) {
    throw 'Weekly learning did not deduplicate a previously processed task.'
}

$multiInputStart = (& (Join-Path $tmpRoot 'scripts\invoke-weekly-harness-learning.ps1') -Mode Start -CodexHome $tmpRoot -SkipHealth) | ConvertFrom-Json
$inputPath = Write-InputFixture -RunId $multiInputStart.run_id
$extraInputPath = Join-Path ([System.IO.Path]::GetFullPath($env:TEMP)) ("codex-weekly-input-$($multiInputStart.run_id)-extra.json")
Set-Content -LiteralPath $extraInputPath -Value '{}' -Encoding UTF8
try {
    & (Join-Path $tmpRoot 'scripts\invoke-weekly-harness-learning.ps1') -Mode Complete -CodexHome $tmpRoot -RunId $multiInputStart.run_id -InputPath $inputPath | Out-Null
    throw 'Expected multiple owned TEMP inputs to fail closed.'
} catch {
    if ($_.Exception.Message -eq 'Expected multiple owned TEMP inputs to fail closed.') { throw }
    if ($_.Exception.Message -notmatch 'exactly one owned TEMP input') {
        throw "Unexpected multiple-input failure: $($_.Exception.Message)"
    }
}
if ((Test-Path -LiteralPath $inputPath) -or (Test-Path -LiteralPath $extraInputPath) -or
    (Test-Path -LiteralPath (Join-Path $tmpRoot 'harness-learning\active-run.json'))) {
    throw 'Weekly learning did not clean all owned TEMP inputs and release its lock after a multiple-input violation.'
}

$unregisteredStart = (& (Join-Path $tmpRoot 'scripts\invoke-weekly-harness-learning.ps1') -Mode Start -CodexHome $tmpRoot -SkipHealth) | ConvertFrom-Json
$unregisteredInputPath = Join-Path ([System.IO.Path]::GetFullPath($env:TEMP)) ("codex-weekly-input-$($unregisteredStart.run_id)-unregistered.json")
Set-Content -LiteralPath $unregisteredInputPath -Value '{}' -Encoding UTF8
try {
    & (Join-Path $tmpRoot 'scripts\invoke-weekly-harness-learning.ps1') -Mode Complete -CodexHome $tmpRoot -RunId $unregisteredStart.run_id -InputPath $unregisteredInputPath | Out-Null
    throw 'Expected an unregistered TEMP input to fail closed.'
} catch {
    if ($_.Exception.Message -eq 'Expected an unregistered TEMP input to fail closed.') { throw }
    if ($_.Exception.Message -notmatch 'not registered by the restricted hook') {
        throw "Unexpected unregistered-input failure: $($_.Exception.Message)"
    }
}
if ((Test-Path -LiteralPath $unregisteredInputPath) -or
    (Test-Path -LiteralPath (Join-Path $tmpRoot 'harness-learning\active-run.json'))) {
    throw 'Weekly learning did not clean an unregistered TEMP input and release its lock.'
}

$oversizedStart = (& (Join-Path $tmpRoot 'scripts\invoke-weekly-harness-learning.ps1') -Mode Start -CodexHome $tmpRoot -SkipHealth) | ConvertFrom-Json
$oversizedInputPath = Join-Path ([System.IO.Path]::GetFullPath($env:TEMP)) ("codex-weekly-input-$($oversizedStart.run_id)-oversized.json")
Set-Content -LiteralPath $oversizedInputPath -Value ('x' * 262145) -Encoding UTF8
Register-InputPath -RunId $oversizedStart.run_id -Path $oversizedInputPath
try {
    & (Join-Path $tmpRoot 'scripts\invoke-weekly-harness-learning.ps1') -Mode Complete -CodexHome $tmpRoot -RunId $oversizedStart.run_id -InputPath $oversizedInputPath | Out-Null
    throw 'Expected an oversized TEMP input to fail closed.'
} catch {
    if ($_.Exception.Message -eq 'Expected an oversized TEMP input to fail closed.') { throw }
    if ($_.Exception.Message -notmatch 'exceeds the 256 KiB limit') {
        throw "Unexpected oversized-input failure: $($_.Exception.Message)"
    }
}
if ((Test-Path -LiteralPath $oversizedInputPath) -or
    (Test-Path -LiteralPath (Join-Path $tmpRoot 'harness-learning\active-run.json'))) {
    throw 'Weekly learning did not clean an oversized TEMP input and release its lock.'
}

$blockedStart = (& (Join-Path $tmpRoot 'scripts\invoke-weekly-harness-learning.ps1') -Mode Start -CodexHome $tmpRoot -SkipHealth) | ConvertFrom-Json
Set-Content -LiteralPath (Join-Path $tmpRoot 'AGENTS.md') -Value '# Proposal-only root instruction change' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $tmpRoot 'config.toml') -Value '[features]`nhooks = false' -Encoding UTF8
$inputPath = Write-InputFixture -RunId $blockedStart.run_id
try {
    & (Join-Path $tmpRoot 'scripts\invoke-weekly-harness-learning.ps1') -Mode Complete -CodexHome $tmpRoot -RunId $blockedStart.run_id -InputPath $inputPath | Out-Null
    throw 'Expected blocked weekly learning run to fail closed.'
} catch {
    if ($_.Exception.Message -eq 'Expected blocked weekly learning run to fail closed.') { throw }
}
$blockedReport = Get-Content -LiteralPath (Join-Path $tmpRoot ("harness-learning\runs\$($blockedStart.run_id)\report.json")) -Raw -Encoding UTF8 | ConvertFrom-Json
if ($blockedReport.status -ne 'blocked' -or
    @($blockedReport.violations | Where-Object { $_ -match 'AGENTS\.md' }).Count -eq 0 -or
    @($blockedReport.violations | Where-Object { $_ -match 'config\.toml' }).Count -eq 0) {
    throw 'Weekly learning did not block proposal-only instruction or protected config changes.'
}

$allowedStart = (& (Join-Path $tmpRoot 'scripts\invoke-weekly-harness-learning.ps1') -Mode Start -CodexHome $tmpRoot -SkipHealth) | ConvertFrom-Json
Add-Content -LiteralPath (Join-Path $tmpRoot 'docs\weekly-learning.md') -Value "`r`nBounded evidence note."
$inputPath = Write-InputFixture -RunId $allowedStart.run_id
try {
    & (Join-Path $tmpRoot 'scripts\invoke-weekly-harness-learning.ps1') -Mode Complete -CodexHome $tmpRoot -RunId $allowedStart.run_id -InputPath $inputPath | Out-Null
    throw 'Expected unattended documentation edit to fail closed.'
} catch {
    if ($_.Exception.Message -eq 'Expected unattended documentation edit to fail closed.') { throw }
}
$unattendedReport = Get-Content -LiteralPath (Join-Path $tmpRoot ("harness-learning\runs\$($allowedStart.run_id)\report.json")) -Raw -Encoding UTF8 | ConvertFrom-Json
if ($unattendedReport.status -ne 'blocked') {
    throw 'Weekly learning allowed an unattended maintainable documentation change.'
}

$failureStart = (& (Join-Path $tmpRoot 'scripts\invoke-weekly-harness-learning.ps1') -Mode Start -CodexHome $tmpRoot -SkipHealth) | ConvertFrom-Json
$invalidInputPath = Join-Path ([System.IO.Path]::GetFullPath($env:TEMP)) ("codex-weekly-input-$($failureStart.run_id)-invalid.json")
Set-Content -LiteralPath $invalidInputPath -Value '{not-json' -Encoding UTF8
Register-InputPath -RunId $failureStart.run_id -Path $invalidInputPath
try {
    & (Join-Path $tmpRoot 'scripts\invoke-weekly-harness-learning.ps1') -Mode Complete -CodexHome $tmpRoot -RunId $failureStart.run_id -InputPath $invalidInputPath | Out-Null
    throw 'Expected invalid input to fail.'
} catch {
    if ($_.Exception.Message -eq 'Expected invalid input to fail.') { throw }
}
if (Test-Path -LiteralPath (Join-Path $tmpRoot 'harness-learning\active-run.json')) {
    throw 'Weekly learning retained an active lock after a failed completion.'
}

$corruptActivePath = Join-Path $tmpRoot 'harness-learning\active-run.json'
Set-Content -LiteralPath $corruptActivePath -Value '{broken-active-lock' -Encoding UTF8
$recoveredStart = (& (Join-Path $tmpRoot 'scripts\invoke-weekly-harness-learning.ps1') -Mode Start -CodexHome $tmpRoot -SkipHealth) | ConvertFrom-Json
if ($recoveredStart.status -ne 'success' -or
    @(Get-ChildItem -LiteralPath (Join-Path $tmpRoot 'harness-learning\runs') -Filter 'corrupt-active-run-*.json').Count -lt 1) {
    throw 'Weekly learning did not recover from a corrupt active-run lock.'
}
$inputPath = Write-InputFixture -RunId $recoveredStart.run_id
& (Join-Path $tmpRoot 'scripts\invoke-weekly-harness-learning.ps1') -Mode Complete -CodexHome $tmpRoot -RunId $recoveredStart.run_id -InputPath $inputPath | Out-Null

$stateRecoveryStart = (& (Join-Path $tmpRoot 'scripts\invoke-weekly-harness-learning.ps1') -Mode Start -CodexHome $tmpRoot -SkipHealth) | ConvertFrom-Json
Set-Content -LiteralPath (Join-Path $tmpRoot 'harness-learning\state.json') -Value '{broken-state' -Encoding UTF8
$inputPath = Write-InputFixture -RunId $stateRecoveryStart.run_id
$stateRecoveryComplete = (& (Join-Path $tmpRoot 'scripts\invoke-weekly-harness-learning.ps1') -Mode Complete -CodexHome $tmpRoot -RunId $stateRecoveryStart.run_id -InputPath $inputPath) | ConvertFrom-Json
if (-not $stateRecoveryComplete.state_recovered -or
    @(Get-ChildItem -LiteralPath (Join-Path $tmpRoot 'harness-learning') -Filter 'state.corrupt-*.json').Count -lt 1) {
    throw 'Weekly learning did not archive and recover a corrupt state file.'
}

$deleteFailureStart = (& (Join-Path $tmpRoot 'scripts\invoke-weekly-harness-learning.ps1') -Mode Start -CodexHome $tmpRoot -SkipHealth) | ConvertFrom-Json
$inputPath = Write-InputFixture -RunId $deleteFailureStart.run_id
$heldInput = [System.IO.File]::Open($inputPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
try {
    try {
        & (Join-Path $tmpRoot 'scripts\invoke-weekly-harness-learning.ps1') -Mode Complete -CodexHome $tmpRoot -RunId $deleteFailureStart.run_id -InputPath $inputPath | Out-Null
        throw 'Expected TEMP deletion failure to fail closed.'
    } catch {
        if ($_.Exception.Message -eq 'Expected TEMP deletion failure to fail closed.') { throw }
        if ($_.Exception.Message -notmatch 'could not delete its temporary input') {
            throw "Unexpected TEMP deletion failure: $($_.Exception.Message)"
        }
    }
} finally {
    $heldInput.Dispose()
}
if (Test-Path -LiteralPath (Join-Path $tmpRoot 'harness-learning\active-run.json')) {
    throw 'Weekly learning retained an active lock after TEMP deletion failed.'
}
if (Test-Path -LiteralPath $inputPath) {
    Remove-Item -LiteralPath $inputPath -Force
}

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $tmpRoot 'scripts\invoke-weekly-harness-learning.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw 'Weekly learning script failed parser inspection.' }
$parameterNames = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
foreach ($legacyParameter in @('ApprovedMaintenance', 'SyncSource', 'SourceProjectRoot', 'SkipVerification')) {
    if ($legacyParameter -in $parameterNames) {
        throw "Weekly learning still exposes maintenance or sync control: $legacyParameter"
    }
}

[ordered]@{
    schema = 'codex-weekly-harness-learning-test-v1'
    status = 'success'
    checks = @(
        'sanitized-persistence',
        'task-and-finding-deduplication',
        'temporary-input-cleanup',
        'single-owned-temp-input',
        'registered-temp-input-only',
        'oversized-temp-input-cleanup',
        'official-public-url-filtering',
        'proposal-only-path-blocking',
        'unattended-maintainable-change-blocking',
        'failed-run-lock-recovery',
        'corrupt-active-lock-recovery',
        'corrupt-state-recovery',
        'temp-delete-failure-closure',
        'no-maintenance-or-sync-switches'
    )
    temporary_artifacts = $tmpRoot
} | ConvertTo-Json -Depth 6 -Compress
