param(
    [ValidateSet("Fast", "Standard", "Full")]
    [string]$Level = "Fast",
    [string]$ProjectRoot = "",
    [string]$CodexHome = "$env:USERPROFILE\.codex",
    [switch]$InstallRuntime,
    [switch]$SkipGitChecks,
    [ValidateRange(1, 3600)]
    [int]$StepTimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"

function Get-StringSha256 {
    param([AllowEmptyString()][string]$Value)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-JsonAtomically {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $tempPath = Join-Path $parent ((Split-Path -Leaf $Path) + ".tmp-" + [guid]::NewGuid().ToString("N"))
    $encoding = New-Object System.Text.UTF8Encoding($false)
    try {
        [System.IO.File]::WriteAllText($tempPath, ($Value | ConvertTo-Json -Depth 12), $encoding)
        Move-Item -LiteralPath $tempPath -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
            Remove-Item -LiteralPath $tempPath -Force
        }
    }
}

function ConvertTo-PowerShellLiteral {
    param([AllowNull()]$Value)

    if ($null -eq $Value) { return '$null' }
    if ($Value -is [bool]) { return $(if ($Value) { '$true' } else { '$false' }) }
    if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64]) {
        return [string]$Value
    }
    return "'" + ([string]$Value).Replace("'", "''") + "'"
}

function New-ScriptCommandText {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [System.Collections.IDictionary]$Parameters = ([ordered]@{}),
        [System.Collections.IDictionary]$Environment = ([ordered]@{})
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('$ErrorActionPreference = "Stop"') | Out-Null
    foreach ($entry in $Environment.GetEnumerator()) {
        $name = [string]$entry.Key
        if ($name -notmatch '^[A-Z0-9_]+$') {
            throw "Unsafe release environment variable name: $name"
        }
        $lines.Add(("`$env:{0} = {1}" -f $name, (ConvertTo-PowerShellLiteral -Value $entry.Value))) | Out-Null
    }

    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add("& " + (ConvertTo-PowerShellLiteral -Value $ScriptPath)) | Out-Null
    foreach ($entry in $Parameters.GetEnumerator()) {
        $name = [string]$entry.Key
        if ($name -notmatch '^[A-Za-z][A-Za-z0-9]*$') {
            throw "Unsafe release parameter name: $name"
        }
        if ($entry.Value -is [System.Management.Automation.SwitchParameter] -or $entry.Value -is [bool]) {
            if ([bool]$entry.Value) { $parts.Add("-$name") | Out-Null }
            continue
        }
        $parts.Add("-$name") | Out-Null
        $parts.Add((ConvertTo-PowerShellLiteral -Value $entry.Value)) | Out-Null
    }
    $lines.Add(($parts -join ' ')) | Out-Null
    $lines.Add('if (-not $?) { throw "Release child script reported failure." }') | Out-Null
    return $lines -join "`r`n"
}

function Stop-ReleaseProcessTree {
    param([Parameter(Mandatory = $true)][int]$ProcessId)

    $taskkill = Get-Command taskkill.exe -ErrorAction SilentlyContinue
    if ($taskkill) {
        try {
            Start-Process -FilePath $taskkill.Source -ArgumentList @('/PID', [string]$ProcessId, '/T', '/F') -WindowStyle Hidden -Wait | Out-Null
            return
        } catch { }
    }
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

function Invoke-BoundedPowerShell {
    param(
        [Parameter(Mandatory = $true)][string]$CommandText,
        [Parameter(Mandatory = $true)][string]$StepName
    )

    $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
    $safeName = $StepName -replace '[^A-Za-z0-9_.-]', '-'
    $token = [guid]::NewGuid().ToString("N")
    $stdoutPath = Join-Path $env:TEMP ("codex-release-{0}-{1}-{2}.stdout" -f $releaseId, $safeName, $token)
    $stderrPath = Join-Path $env:TEMP ("codex-release-{0}-{1}-{2}.stderr" -f $releaseId, $safeName, $token)
    $statusPath = Join-Path $env:TEMP ("codex-release-{0}-{1}-{2}.status" -f $releaseId, $safeName, $token)
    $statusLiteral = ConvertTo-PowerShellLiteral -Value $statusPath
    $wrappedCommand = @(
        '$ErrorActionPreference = "Stop"',
        'try {',
        $CommandText,
        "    [System.IO.File]::WriteAllText($statusLiteral, 'success')",
        '} catch {',
        "    [System.IO.File]::WriteAllText($statusLiteral, 'failed')",
        '    [Console]::Error.WriteLine($_.Exception.Message)',
        '    exit 1',
        '}'
    ) -join "`r`n"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($wrappedCommand))
    $process = $null
    $timedOut = $false
    $exitCode = -1
    try {
        $process = Start-Process -FilePath $powershell `
            -ArgumentList @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded) `
            -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        if (-not $process.WaitForExit($StepTimeoutSeconds * 1000)) {
            $timedOut = $true
            Stop-ReleaseProcessTree -ProcessId $process.Id
            $null = $process.WaitForExit(5000)
        }
        if ($process.HasExited) {
            $process.WaitForExit()
            $exitCode = $process.ExitCode
        }
        $status = if (Test-Path -LiteralPath $statusPath -PathType Leaf) { (Get-Content -LiteralPath $statusPath -Raw).Trim() } else { '' }
        if ($status -eq 'success') {
            $exitCode = 0
        } elseif ($status -eq 'failed') {
            $exitCode = 1
        } elseif (-not $timedOut) {
            $exitCode = -1
        }
        $stdout = if (Test-Path -LiteralPath $stdoutPath -PathType Leaf) { Get-Content -LiteralPath $stdoutPath -Raw } else { "" }
        $stderr = if (Test-Path -LiteralPath $stderrPath -PathType Leaf) { Get-Content -LiteralPath $stderrPath -Raw } else { "" }
        return [pscustomobject]@{
            stdout = [string]$stdout
            stderr = [string]$stderr
            exit_code = $exitCode
            timed_out = $timedOut
        }
    } finally {
        if ($process) { $process.Dispose() }
        foreach ($path in @($stdoutPath, $stderrPath, $statusPath)) {
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Write-ReleaseManifest {
    $manifest.steps = $steps.ToArray()
    Write-JsonAtomically -Path $manifestPath -Value $manifest
}

function Add-ReleaseStepRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][double]$Seconds,
        [bool]$TimedOut = $false,
        [int]$ExitCode = 0,
        [AllowEmptyString()][string]$Output = ""
    )

    $steps.Add([pscustomobject]@{
        name = $Name
        status = $Status
        seconds = [math]::Round($Seconds, 3)
        timed_out = $TimedOut
        exit_code = $ExitCode
        output_sha256 = Get-StringSha256 -Value $Output
    }) | Out-Null
    Write-ReleaseManifest
}

function Invoke-ReleaseCommandStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$CommandText
    )

    $script:currentStepName = $Name
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $result = Invoke-BoundedPowerShell -CommandText $CommandText -StepName $Name
        $sw.Stop()
        $combined = @($result.stdout, $result.stderr) -join "`n"
        $stepTimedOut = [bool]$result.timed_out
        $stepExitCode = [int]$result.exit_code
        $passed = (-not $stepTimedOut) -and ($stepExitCode -eq 0)
        Add-ReleaseStepRecord -Name $Name -Status $(if ($passed) { "passed" } else { "failed" }) `
            -Seconds $sw.Elapsed.TotalSeconds -TimedOut $stepTimedOut -ExitCode $stepExitCode -Output $combined
        if (-not $passed) {
            $script:lastStepTimedOut = $stepTimedOut
            $script:lastStepOutputHash = Get-StringSha256 -Value $combined
            throw "Release step failed: $Name"
        }
        return $result
    } catch {
        if ($sw.IsRunning) { $sw.Stop() }
        if (@($steps | Where-Object { $_.name -eq $Name }).Count -eq 0) {
            $messageHash = Get-StringSha256 -Value $_.Exception.Message
            Add-ReleaseStepRecord -Name $Name -Status "failed" -Seconds $sw.Elapsed.TotalSeconds -ExitCode -1 -Output $messageHash
            $script:lastStepOutputHash = $messageHash
        }
        throw
    }
}

function Invoke-ReleaseScriptStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [System.Collections.IDictionary]$Parameters = ([ordered]@{}),
        [System.Collections.IDictionary]$Environment = ([ordered]@{})
    )

    $commandText = New-ScriptCommandText -ScriptPath $ScriptPath -Parameters $Parameters -Environment $Environment
    return Invoke-ReleaseCommandStep -Name $Name -CommandText $commandText
}

function Invoke-InternalReleaseStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Script
    )

    $script:currentStepName = $Name
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $output = & $Script
        $sw.Stop()
        $safeOutput = if ($null -eq $output) { "passed" } else { ($output | ConvertTo-Json -Depth 6 -Compress) }
        Add-ReleaseStepRecord -Name $Name -Status "passed" -Seconds $sw.Elapsed.TotalSeconds -Output $safeOutput
        return $output
    } catch {
        $sw.Stop()
        $errorHash = Get-StringSha256 -Value $_.Exception.Message
        Add-ReleaseStepRecord -Name $Name -Status "failed" -Seconds $sw.Elapsed.TotalSeconds -ExitCode -1 -Output $errorHash
        $script:lastStepOutputHash = $errorHash
        throw
    }
}

function ConvertFrom-StepJson {
    param([Parameter(Mandatory = $true)]$StepResult)

    $candidate = $null
    foreach ($line in @(([string]$StepResult.stdout) -split '\r?\n')) {
        $trimmed = $line.Trim()
        if (-not $trimmed.StartsWith("{")) { continue }
        try { $candidate = $trimmed | ConvertFrom-Json } catch { }
    }
    if (-not $candidate) {
        throw "Release step did not return JSON output."
    }
    return $candidate
}

function Test-ForbiddenPayloadPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $excludedDirectories = @(
        '__pycache__', '.codex-trash', '.sandbox', '.sandbox-bin', '.sandbox-secrets', '.tmp', 'tmp',
        'plugins', 'plugin', 'cache', 'caches', 'session', 'sessions', 'archived_sessions', 'log', 'logs',
        'hook-logs', 'browser', 'browser-state', 'browser_state', 'computer-use', 'process_manager',
        'harness-health', 'harness-changes', 'harness-learning', 'skills.archived', 'agents.archived',
        'backups', 'archived', 'database', 'databases', 'runs'
    )
    $segments = $RelativePath -split '[\\/]'
    $directories = @($segments | Select-Object -First ([math]::Max(0, $segments.Count - 1)))
    $name = $segments[-1]
    if (@($directories | Where-Object { $_ -in $excludedDirectories -or $_ -like 'backup-*' }).Count -gt 0) { return $true }
    if ($name -in @('auth.json', 'config.toml', '.sync-manifest.json', '.codex-private')) { return $true }
    if ($name -like '*.sqlite*' -or $name -match '(?i)\.(db|db3|sdb|db-wal|db-shm|pyc|pyo)$') { return $true }
    if ($name -match '(?i)\.bak(?:[-.].*)?$|\.backup(?:[-.].*)?$|~$') { return $true }
    return $false
}

function Assert-StagingBoundary {
    param([Parameter(Mandatory = $true)][string]$Root)

    $resolvedRoot = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Root).Path).TrimEnd('\')
    $prefix = $resolvedRoot + '\'
    $forbidden = New-Object System.Collections.Generic.List[string]
    foreach ($item in @(Get-ChildItem -LiteralPath $resolvedRoot -Recurse -Force)) {
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Staging contains a reparse point."
        }
        if (-not $item.PSIsContainer) {
            $relative = $item.FullName.Substring($prefix.Length)
            if (Test-ForbiddenPayloadPath -RelativePath $relative) { $forbidden.Add($relative) | Out-Null }
        }
    }
    if ($forbidden.Count -gt 0) {
        throw "Staging contains forbidden runtime state."
    }
    return [pscustomobject]@{ file_count = @(Get-ChildItem -LiteralPath $resolvedRoot -Recurse -Force -File).Count }
}

function Remove-GeneratedReleaseDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    $full = [System.IO.Path]::GetFullPath($Path)
    $releasePrefix = [System.IO.Path]::GetFullPath($releaseRoot).TrimEnd('\') + '\'
    if (-not $full.StartsWith($releasePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a directory outside the release run."
    }
    [System.IO.Directory]::Delete($full, $true)
}

function Remove-StagingGeneratedEvidence {
    $removed = 0
    foreach ($relative in @(
        'harness-health',
        'harness-evals\runs',
        'harness-evals\trace-evals\runs',
        'harness-evals\trace-evals\summaries'
    )) {
        $path = Join-Path $stagingRoot $relative
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { continue }
        Remove-GeneratedReleaseDirectory -Path $path
        $removed++
    }
    return [pscustomobject]@{ removed_directories = $removed }
}

function Assert-RuntimeInstallCanary {
    param([Parameter(Mandatory = $true)][string]$TransactionManifest)

    $transaction = Get-Content -LiteralPath $TransactionManifest -Raw | ConvertFrom-Json
    if ([string]$transaction.schema -ne 'codex-harness-sync-transaction-v2' -or [string]$transaction.status -ne 'installed') {
        throw "Runtime transaction is not in the installed state."
    }
    if ([string]$transaction.source_fingerprint -ne [string]$manifest.source.fingerprint_sha256) {
        throw "Runtime transaction source fingerprint differs from staging."
    }
    $runtimeRoot = [System.IO.Path]::GetFullPath($CodexHome)
    $runtimePrefix = $runtimeRoot.TrimEnd('\') + '\'
    foreach ($entry in @($transaction.files)) {
        $relative = [string]$entry.relative_path
        if (Test-ForbiddenPayloadPath -RelativePath $relative) {
            throw "Runtime transaction includes a forbidden path."
        }
        $target = [System.IO.Path]::GetFullPath((Join-Path $runtimeRoot $relative))
        if (-not $target.StartsWith($runtimePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Runtime transaction target escaped Codex home."
        }
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            throw "Installed runtime file is missing."
        }
        if ((Get-FileSha256 -Path $target) -ne [string]$entry.source_sha256) {
            throw "Installed runtime file hash differs from staging."
        }
    }
    return [pscustomobject]@{ verified_files = @($transaction.files).Count }
}

function Assert-RuntimeRollbackCanary {
    param([Parameter(Mandatory = $true)][string]$TransactionManifest)

    $transaction = Get-Content -LiteralPath $TransactionManifest -Raw | ConvertFrom-Json
    if ([string]$transaction.status -ne 'rolled-back' -or [string]$transaction.rollback.status -ne 'rolled-back') {
        throw "Runtime transaction did not record a completed rollback."
    }
    $runtimeRoot = [System.IO.Path]::GetFullPath($CodexHome)
    foreach ($entry in @($transaction.files)) {
        $target = Join-Path $runtimeRoot ([string]$entry.relative_path)
        if ([bool]$entry.target_existed) {
            if (-not (Test-Path -LiteralPath $target -PathType Leaf) -or
                (Get-FileSha256 -Path $target) -ne [string]$entry.target_sha256_before) {
                throw "Rollback did not restore a prior maintainable file."
            }
        } elseif (Test-Path -LiteralPath $target) {
            throw "Rollback did not remove a newly installed maintainable file."
        }
    }
    return [pscustomobject]@{
        restored_files = [int]$transaction.rollback.restored_files
        removed_files = [int]$transaction.rollback.removed_files
    }
}

if (-not $ProjectRoot) {
    $ProjectRoot = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path)
} else {
    $ProjectRoot = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).Path)
}

if ($Level -eq 'Fast' -and $InstallRuntime) {
    throw "Fast release verification does not install runtime. Use -Level Standard or -Level Full."
}
if ($InstallRuntime -and -not (Test-Path -LiteralPath $CodexHome -PathType Container)) {
    throw "Codex home does not exist: $CodexHome"
}
$CodexHome = [System.IO.Path]::GetFullPath($CodexHome)
$runDeterministicEvals = ($Level -eq 'Full' -or [bool]$InstallRuntime)

$releaseId = [guid]::NewGuid().ToString('N')
$releaseDirectory = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmssfff') + '-' + $releaseId.Substring(0, 12)
$releaseRoot = Join-Path $ProjectRoot (Join-Path 'artifacts\release-runs' $releaseDirectory)
$manifestPath = Join-Path $releaseRoot 'release-manifest.json'
$stagingRoot = Join-Path $releaseRoot 'staging-codex-home'
$transactionRoot = Join-Path $releaseRoot 'runtime-transaction'
$transactionManifestPath = Join-Path $transactionRoot 'sync-transaction.json'
New-Item -ItemType Directory -Force -Path $releaseRoot | Out-Null

$steps = New-Object System.Collections.Generic.List[object]
$manifest = [ordered]@{
    schema = 'codex-harness-release-v2'
    release_id = $releaseId
    created_at = (Get-Date).ToUniversalTime().ToString('o')
    completed_at = $null
    status = 'running'
    level = $Level
    install_requested = [bool]$InstallRuntime
    source = [ordered]@{
        fingerprint_sha256 = ''
        file_count = 0
    }
    staging = [ordered]@{
        status = if ($Level -in @('Standard', 'Full')) { 'pending' } else { 'not-requested' }
        file_count = 0
        boundary_checks = 0
        global_verify_runs = 0
        deterministic_eval_runs = 0
        cleanup_status = if ($Level -in @('Standard', 'Full')) { 'pending' } else { 'not-requested' }
    }
    install = [ordered]@{
        status = if ($InstallRuntime) { 'pending' } else { 'not-requested' }
        global_verify_runs = 0
        canary_runs = 0
        transaction_schema = ''
        transaction_manifest_sha256 = ''
        rollback = [ordered]@{
            status = 'not-needed'
            restored_files = 0
            removed_files = 0
        }
    }
    failure = [ordered]@{
        step = ''
        timed_out = $false
        error_sha256 = ''
    }
    steps = @()
}
Write-ReleaseManifest

$currentStepName = ''
$lastStepTimedOut = $false
$lastStepOutputHash = ''
$installStarted = $false
$exitCode = 0

try {
    if (-not $SkipGitChecks) {
        $rootLiteral = ConvertTo-PowerShellLiteral -Value $ProjectRoot
        $gitCommand = @(
            '$ErrorActionPreference = "Stop"',
            "& git -C $rootLiteral diff --check",
            'if ($LASTEXITCODE -ne 0) { throw "git diff --check failed." }',
            "& git -C $rootLiteral diff --cached --check",
            'if ($LASTEXITCODE -ne 0) { throw "git diff --cached --check failed." }'
        ) -join "`r`n"
        Invoke-ReleaseCommandStep -Name 'git-diff-check' -CommandText $gitCommand | Out-Null
    }

    Invoke-ReleaseScriptStep -Name 'package-public-readiness' `
        -ScriptPath (Join-Path $ProjectRoot 'deploy\verify-package.ps1') `
        -Parameters ([ordered]@{ ProjectRoot = $ProjectRoot }) | Out-Null
    Invoke-ReleaseScriptStep -Name 'source-sync-boundaries' `
        -ScriptPath (Join-Path $ProjectRoot 'deploy\test-sync-boundaries.ps1') `
        -Parameters ([ordered]@{ ProjectRoot = $ProjectRoot }) | Out-Null
    if (-not $runDeterministicEvals) {
        Invoke-ReleaseScriptStep -Name 'source-optimizer-self-test' `
            -ScriptPath (Join-Path $ProjectRoot 'src\harness-evals\test-project-harness-optimizer.ps1') `
            -Parameters ([ordered]@{ CodexHome = (Join-Path $ProjectRoot 'src') }) | Out-Null
        Invoke-ReleaseScriptStep -Name 'source-context-budget' `
            -ScriptPath (Join-Path $ProjectRoot 'src\scripts\audit-context-budget.ps1') `
            -Parameters ([ordered]@{ ProjectRoot = $ProjectRoot; CodexHome = (Join-Path $ProjectRoot 'src') }) | Out-Null
        Invoke-ReleaseScriptStep -Name 'source-component-registry' `
            -ScriptPath (Join-Path $ProjectRoot 'src\scripts\audit-harness-components.ps1') `
            -Parameters ([ordered]@{ ProjectRoot = (Join-Path $ProjectRoot 'src') }) | Out-Null
    }

    if ($Level -eq 'Standard' -and -not $runDeterministicEvals) {
        Invoke-ReleaseScriptStep -Name 'source-workflow-core' `
            -ScriptPath (Join-Path $ProjectRoot 'src\scripts\test-codex-workflow-core.ps1') `
            -Parameters ([ordered]@{ CodexHome = (Join-Path $ProjectRoot 'src') }) | Out-Null
        Invoke-ReleaseScriptStep -Name 'source-verification-gate' `
            -ScriptPath (Join-Path $ProjectRoot 'src\harness-evals\test-verification-gate.ps1') `
            -Parameters ([ordered]@{ CodexHome = (Join-Path $ProjectRoot 'src') }) | Out-Null
        Invoke-ReleaseScriptStep -Name 'source-verification-envelope' `
            -ScriptPath (Join-Path $ProjectRoot 'src\harness-evals\test-verification-envelope.ps1') `
            -Parameters ([ordered]@{ CodexHome = (Join-Path $ProjectRoot 'src') }) | Out-Null
    }

    if ($Level -in @('Standard', 'Full')) {
        New-Item -ItemType Directory -Force -Path $stagingRoot | Out-Null
        $stageSyncStep = Invoke-ReleaseScriptStep -Name 'staging-source-sync' `
            -ScriptPath (Join-Path $ProjectRoot 'deploy\sync-to-runtime.ps1') `
            -Parameters ([ordered]@{ ProjectRoot = $ProjectRoot; CodexHome = $stagingRoot; NoBackup = $true })
        $stageSync = ConvertFrom-StepJson -StepResult $stageSyncStep
        $manifest.source.fingerprint_sha256 = [string]$stageSync.source_fingerprint
        $manifest.source.file_count = [int]$stageSync.source_file_count
        $manifest.staging.file_count = [int]$stageSync.copied_file_count
        Write-ReleaseManifest

        $stageBoundary = Invoke-InternalReleaseStep -Name 'staging-maintainable-boundary' -Script {
            Assert-StagingBoundary -Root $stagingRoot
        }
        $manifest.staging.file_count = [int]$stageBoundary.file_count
        $manifest.staging.boundary_checks++
        Write-ReleaseManifest

        $manifest.staging.global_verify_runs++
        Write-ReleaseManifest
        Invoke-ReleaseScriptStep -Name 'staging-global-verify' `
            -ScriptPath (Join-Path $stagingRoot 'scripts\verify-global-harness.ps1') `
            -Parameters ([ordered]@{ CodexHome = $stagingRoot }) `
            -Environment ([ordered]@{ CODEX_RELEASE_STAGE = '1'; CODEX_RELEASE_STAGING_ROOT = $stagingRoot }) | Out-Null

        if ($runDeterministicEvals) {
            $manifest.staging.deterministic_eval_runs++
            Write-ReleaseManifest
            Invoke-ReleaseScriptStep -Name 'staging-harness-evals' `
                -ScriptPath (Join-Path $stagingRoot 'harness-evals\run-harness-evals.ps1') `
                -Parameters ([ordered]@{ CodexHome = $stagingRoot }) `
                -Environment ([ordered]@{ CODEX_RELEASE_STAGE = '1'; CODEX_RELEASE_STAGING_ROOT = $stagingRoot }) | Out-Null
            Invoke-InternalReleaseStep -Name 'staging-generated-evidence-cleanup' -Script {
                Remove-StagingGeneratedEvidence
            } | Out-Null
        }

        Invoke-InternalReleaseStep -Name 'staging-post-verify-boundary' -Script {
            Assert-StagingBoundary -Root $stagingRoot
        } | Out-Null
        $manifest.staging.boundary_checks++
        $manifest.staging.status = 'verified'
        Write-ReleaseManifest
    }

    if ($InstallRuntime) {
        $installStarted = $true
        $installStep = Invoke-ReleaseScriptStep -Name 'runtime-sync-install' `
            -ScriptPath (Join-Path $ProjectRoot 'deploy\sync-to-runtime.ps1') `
            -Parameters ([ordered]@{ ProjectRoot = $ProjectRoot; CodexHome = $CodexHome; TransactionRoot = $transactionRoot })
        $installResult = ConvertFrom-StepJson -StepResult $installStep
        $transactionManifestPath = [string]$installResult.transaction_manifest
        $transaction = Get-Content -LiteralPath $transactionManifestPath -Raw | ConvertFrom-Json
        $manifest.install.transaction_schema = [string]$transaction.schema
        $manifest.install.transaction_manifest_sha256 = Get-FileSha256 -Path $transactionManifestPath
        $manifest.install.status = 'installed'
        Write-ReleaseManifest

        $manifest.install.global_verify_runs++
        Write-ReleaseManifest
        Invoke-ReleaseScriptStep -Name 'runtime-global-verify' `
            -ScriptPath (Join-Path $CodexHome 'scripts\verify-global-harness.ps1') `
            -Parameters ([ordered]@{ CodexHome = $CodexHome }) `
            -Environment ([ordered]@{ CODEX_RELEASE_STAGE = '0'; CODEX_RELEASE_STAGING_ROOT = $stagingRoot }) | Out-Null

        $manifest.install.canary_runs++
        Write-ReleaseManifest
        Invoke-InternalReleaseStep -Name 'runtime-install-canary' -Script {
            Assert-RuntimeInstallCanary -TransactionManifest $transactionManifestPath
        } | Out-Null
        $manifest.install.status = 'verified'
        Write-ReleaseManifest
    }

    $manifest.status = 'success'
} catch {
    $exitCode = 1
    $manifest.status = 'failed'
    $manifest.failure.step = [string]$currentStepName
    $manifest.failure.timed_out = [bool]$lastStepTimedOut
    $manifest.failure.error_sha256 = if ($lastStepOutputHash) { $lastStepOutputHash } else { Get-StringSha256 -Value $_.Exception.Message }

    if ($InstallRuntime -and $installStarted -and (Test-Path -LiteralPath $transactionManifestPath -PathType Leaf)) {
        try {
            $transaction = Get-Content -LiteralPath $transactionManifestPath -Raw | ConvertFrom-Json
            if ([string]$transaction.status -ne 'rolled-back') {
                $manifest.install.rollback.status = 'running'
                Write-ReleaseManifest
                $rollbackStep = Invoke-ReleaseScriptStep -Name 'runtime-automatic-rollback' `
                    -ScriptPath (Join-Path $ProjectRoot 'deploy\sync-to-runtime.ps1') `
                    -Parameters ([ordered]@{ CodexHome = $CodexHome; RollbackManifest = $transactionManifestPath })
                $rollbackResult = ConvertFrom-StepJson -StepResult $rollbackStep
                $manifest.install.rollback.restored_files = [int]$rollbackResult.restored_files
                $manifest.install.rollback.removed_files = [int]$rollbackResult.removed_files
            } else {
                $manifest.install.rollback.restored_files = [int]$transaction.rollback.restored_files
                $manifest.install.rollback.removed_files = [int]$transaction.rollback.removed_files
            }
            Invoke-InternalReleaseStep -Name 'runtime-rollback-canary' -Script {
                Assert-RuntimeRollbackCanary -TransactionManifest $transactionManifestPath
            } | Out-Null
            $manifest.install.status = 'rolled-back'
            $manifest.install.rollback.status = 'rolled-back'
            $manifest.install.transaction_manifest_sha256 = Get-FileSha256 -Path $transactionManifestPath
        } catch {
            $manifest.install.status = 'rollback-failed'
            $manifest.install.rollback.status = 'rollback-failed'
            $manifest.failure.error_sha256 = Get-StringSha256 -Value $_.Exception.Message
        }
    } elseif ($InstallRuntime -and $installStarted) {
        $manifest.install.status = 'failed-before-transaction'
    }
} finally {
    $cleanupIncomplete = $false
    foreach ($generated in @($stagingRoot)) {
        try { Remove-GeneratedReleaseDirectory -Path $generated } catch {
            $cleanupIncomplete = $true
        }
    }
    if ($Level -in @('Standard', 'Full')) {
        $manifest.staging.cleanup_status = if ($cleanupIncomplete) { 'incomplete' } else { 'removed' }
    }
    $manifest.completed_at = (Get-Date).ToUniversalTime().ToString('o')
    Write-ReleaseManifest
}

$result = [ordered]@{
    status = $manifest.status
    release_id = $releaseId
    level = $Level
    installed_runtime = [bool]($InstallRuntime -and $manifest.install.status -eq 'verified')
    manifest = $manifestPath
    manifest_sha256 = Get-FileSha256 -Path $manifestPath
    summary = if ($manifest.status -eq 'success') {
        if ($InstallRuntime) { 'Release v2 staged, verified, transactionally installed, and canary-checked.' }
        elseif ($Level -in @('Standard', 'Full')) { 'Release v2 staged and verified without installing runtime.' }
        else { 'Release v2 source checks passed.' }
    } else {
        'Release v2 failed; any started runtime transaction was rolled back when possible.'
    }
} | ConvertTo-Json -Depth 6 -Compress

Write-Output $result
if ($exitCode -ne 0) { exit $exitCode }
