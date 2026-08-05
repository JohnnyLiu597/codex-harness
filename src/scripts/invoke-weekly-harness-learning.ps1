[CmdletBinding()]
param(
    [ValidateSet("Start", "Complete", "DryRun")]
    [string]$Mode = "Start",
    [string]$CodexHome = "$env:USERPROFILE\.codex",
    [string]$RunId = "",
    [string]$InputPath = "",
    [ValidateRange(1, 30)]
    [int]$LookbackDays = 7,
    [ValidateRange(1, 30)]
    [int]$MaxTasks = 12,
    [switch]$SkipHealth
)

$ErrorActionPreference = "Stop"

function Get-ObjectValue {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Default = $null
    )

    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Get-Sha256Text {
    param([AllowEmptyString()][string]$Text)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function ConvertTo-SafeText {
    param(
        [object]$Value,
        [int]$MaxLength = 800
    )

    if ($null -eq $Value) { return "" }
    $text = [string]$Value
    $text = [regex]::Replace($text, '(?i)https?://[^\s<>"'']+', '[url-redacted]')
    $text = [regex]::Replace($text, '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', '[email-redacted]')
    $text = [regex]::Replace($text, '(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+', 'Bearer [redacted]')
    $text = [regex]::Replace(
        $text,
        '(?i)\b(authorization|cookie|set-cookie|password|passwd|secret|token|api[_-]?key)\s*[:=]\s*[^\s,;]+',
        '$1=[redacted]'
    )
    $text = [regex]::Replace($text, '(?i)C:\\Users\\[^\\\r\n]+', 'C:\Users\[user]')
    $text = [regex]::Replace($text, '[\r\n\t]+', ' ')
    $text = [regex]::Replace($text, '\s{2,}', ' ').Trim()
    if ($text.Length -gt $MaxLength) {
        $text = $text.Substring(0, $MaxLength).TrimEnd() + "..."
    }
    return $text
}

function ConvertTo-OfficialPublicUrl {
    param([object]$Value)

    if ($null -eq $Value) { return "" }
    $raw = ([string]$Value).Trim()
    if ($raw.Length -gt 1200) { return "" }
    if ([string]::IsNullOrWhiteSpace($raw)) { return "" }
    try {
        $uri = [Uri]$raw
        if ($uri.Scheme -ne "https") { return "" }
        $hostName = $uri.DnsSafeHost.ToLowerInvariant()
        $isOpenAiHost = $hostName -eq 'openai.com' -or $hostName.EndsWith('.openai.com')
        $isOpenAiGitHub = $hostName -eq 'github.com' -and $uri.AbsolutePath -match '(?i)^/openai(?:/|$)'
        if (-not $isOpenAiHost -and -not $isOpenAiGitHub) { return "" }
        $builder = [UriBuilder]$uri
        $builder.Query = ""
        $builder.Fragment = ""
        $builder.UserName = ""
        $builder.Password = ""
        return $builder.Uri.AbsoluteUri.TrimEnd('/')
    } catch {
        return ""
    }
}

function ConvertTo-PowerShellLiteral {
    param([string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Invoke-BoundedPowerShellScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [hashtable]$Parameters = @{},
        [ValidateRange(1, 3600)][int]$TimeoutSeconds = 180
    )

    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add('& ' + (ConvertTo-PowerShellLiteral -Value $ScriptPath)) | Out-Null
    foreach ($entry in @($Parameters.GetEnumerator() | Sort-Object Key)) {
        if ($entry.Value -is [bool]) {
            if ([bool]$entry.Value) { $parts.Add('-' + [string]$entry.Key) | Out-Null }
            continue
        }
        if ($null -eq $entry.Value) { continue }
        $parts.Add(('-' + [string]$entry.Key + ' ' + (ConvertTo-PowerShellLiteral -Value ([string]$entry.Value)))) | Out-Null
    }

    $command = '[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false); ' + ($parts -join ' ')
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $process = New-Object System.Diagnostics.Process
    try {
        $process.StartInfo = New-Object System.Diagnostics.ProcessStartInfo
        $process.StartInfo.FileName = (Get-Command powershell -ErrorAction Stop).Source
        $process.StartInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill() } catch {}
            throw "Timed out after $TimeoutSeconds seconds: $ScriptPath"
        }
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            throw "Child process exited with code $($process.ExitCode): $stderr"
        }
        return $stdout
    } finally {
        $process.Dispose()
    }
}

function ConvertTo-TaskTimestamp {
    param([object]$Value)

    if ($null -eq $Value) { return $null }
    $raw = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    $seconds = [int64]0
    if ([int64]::TryParse($raw, [ref]$seconds) -and $seconds -gt 1000000000) {
        try { return [DateTimeOffset]::FromUnixTimeSeconds($seconds) } catch { return $null }
    }
    $parsed = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse($raw, [ref]$parsed)) { return $parsed }
    return $null
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Value
    )

    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $temporary = Join-Path $parent ((Split-Path -Leaf $Path) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $json = $Value | ConvertTo-Json -Depth 12
        [System.IO.File]::WriteAllText($temporary, $json, (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-SnapshotExcluded {
    param([string]$RelativePath)

    $path = $RelativePath.Replace('/', '\')
    foreach ($prefix in @(
        'skills\.system\',
        'skills\codex-primary-runtime\',
        'harness-evals\runs\',
        'harness-evals\trace-evals\runs\',
        'harness-evals\trace-evals\summaries\'
    )) {
        if ($path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    if ($path -match '(?i)(^|\\)(__pycache__|\.codex-trash|cache|caches|logs?|sessions?|browser(?:[._-]?state)?|plugins?)(\\|$)') {
        return $true
    }
    $leaf = [System.IO.Path]::GetFileName($path)
    if ($leaf -eq '.sync-manifest.json') { return $true }
    if ($leaf -in @('auth.json', 'config.toml') -and $path -match '\\') { return $true }
    if ($path -match '(?i)\.sqlite|\.py[co]$|\.bak(?:[-.].*)?$|\.backup(?:[-.].*)?$|~$') { return $true }
    return $false
}

function Get-MaintainableSnapshot {
    param([string]$Root)

    $files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    foreach ($name in @('AGENTS.md', 'CODEX.md', 'harness.capabilities.json', 'harness.components.json', 'hooks.json', 'config.toml', 'auth.json', 'requirements.toml')) {
        $path = Join-Path $Root $name
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $files.Add((Get-Item -LiteralPath $path)) | Out-Null
        }
    }
    foreach ($name in @('agents', 'docs', 'rules', 'scripts', 'templates', 'harness-evals', 'skills')) {
        $path = Join-Path $Root $name
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $path -Recurse -Force -File -ErrorAction SilentlyContinue)) {
            $files.Add($file) | Out-Null
        }
    }
    $automationTemplate = Join-Path $Root 'automations\harness\automation.toml.template'
    if (Test-Path -LiteralPath $automationTemplate -PathType Leaf) {
        $files.Add((Get-Item -LiteralPath $automationTemplate)) | Out-Null
    }

    $rootFull = (Get-Item -LiteralPath $Root).FullName
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($file in @($files | Sort-Object FullName -Unique)) {
        $relative = $file.FullName.Substring($rootFull.Length).TrimStart([char[]]@('\', '/'))
        if (Test-SnapshotExcluded -RelativePath $relative) { continue }
        $items.Add([pscustomobject]@{
            path = $relative.Replace('/', '\')
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            bytes = [int64]$file.Length
        }) | Out-Null
    }
    return $items.ToArray()
}

function Compare-Snapshots {
    param(
        [object[]]$Before,
        [object[]]$After
    )

    $beforeMap = @{}
    $afterMap = @{}
    foreach ($item in @($Before)) { $beforeMap[[string]$item.path] = $item }
    foreach ($item in @($After)) { $afterMap[[string]$item.path] = $item }
    $paths = @($beforeMap.Keys + $afterMap.Keys | Sort-Object -Unique)
    $changes = New-Object System.Collections.Generic.List[object]
    foreach ($path in $paths) {
        if (-not $beforeMap.ContainsKey($path)) {
            $changes.Add([pscustomobject]@{ path = $path; change = 'added'; bytes = [int64]$afterMap[$path].bytes }) | Out-Null
        } elseif (-not $afterMap.ContainsKey($path)) {
            $changes.Add([pscustomobject]@{ path = $path; change = 'removed'; bytes = [int64]$beforeMap[$path].bytes }) | Out-Null
        } elseif ($beforeMap[$path].sha256 -ne $afterMap[$path].sha256) {
            $changes.Add([pscustomobject]@{ path = $path; change = 'modified'; bytes = [int64]$afterMap[$path].bytes }) | Out-Null
        }
    }
    return $changes.ToArray()
}

function Merge-UniqueLimited {
    param(
        [object[]]$Existing,
        [object[]]$New,
        [int]$Limit
    )

    $seen = New-Object System.Collections.Generic.HashSet[string]
    $ordered = New-Object System.Collections.Generic.List[string]
    foreach ($value in @($Existing) + @($New)) {
        $text = [string]$value
        if ([string]::IsNullOrWhiteSpace($text) -or -not $seen.Add($text)) { continue }
        $ordered.Add($text) | Out-Null
    }
    if ($ordered.Count -le $Limit) { return $ordered.ToArray() }
    return @($ordered.ToArray() | Select-Object -Last $Limit)
}

function Get-StringArray {
    param([object]$Value)
    if ($null -eq $Value) { return @() }
    return @($Value | ForEach-Object { [string]$_ })
}

$codexHomePath = (Resolve-Path -LiteralPath $CodexHome).Path
$stateRoot = Join-Path $codexHomePath 'harness-learning'
$runsRoot = Join-Path $stateRoot 'runs'
$statePath = Join-Path $stateRoot 'state.json'
$activeRunPath = Join-Path $stateRoot 'active-run.json'
New-Item -ItemType Directory -Force -Path $runsRoot | Out-Null

function Assert-ValidRunId {
    param([string]$Value)
    if ($Value -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,80}$') {
        throw 'RunId must contain only letters, digits, underscore, or hyphen and cannot exceed 81 characters.'
    }
}

$ownedRunId = ''
$ownedRunDir = ''
$releaseOwnedLock = $false

function Close-OwnedRunLock {
    param([string]$Disposition)

    if ([string]::IsNullOrWhiteSpace($ownedRunId) -or [string]::IsNullOrWhiteSpace($ownedRunDir)) { return }
    if (-not (Test-Path -LiteralPath $activeRunPath -PathType Leaf)) { return }
    try {
        $active = Get-Content -LiteralPath $activeRunPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$active.run_id -ne $ownedRunId) { return }
    } catch {
        $Disposition = $Disposition + '-corrupt'
    }
    $target = Join-Path $ownedRunDir ("active-run.$Disposition." + (Get-Date -Format 'yyyyMMdd-HHmmssfff') + '.json')
    Move-Item -LiteralPath $activeRunPath -Destination $target -Force
}

try {
if ($Mode -eq 'Start') {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
    if ([string]::IsNullOrWhiteSpace($RunId)) { $RunId = $stamp }
    Assert-ValidRunId -Value $RunId
    $runDir = Join-Path $runsRoot $RunId
    if (Test-Path -LiteralPath $runDir) { throw "Weekly learning run already exists: $RunId" }
    if (Test-Path -LiteralPath $activeRunPath -PathType Leaf) {
        try {
            $active = Get-Content -LiteralPath $activeRunPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $activeStarted = [DateTimeOffset]::Parse([string]$active.started_at)
            if ($activeStarted -gt [DateTimeOffset]::Now.AddHours(-2)) {
                throw "Another weekly learning run is active: $($active.run_id)"
            }
            $staleLock = Join-Path $runsRoot ("stale-active-run-" + (Get-Date -Format 'yyyyMMdd-HHmmssfff') + '.json')
        } catch {
            if ($_.Exception.Message -like 'Another weekly learning run is active:*') { throw }
            $staleLock = Join-Path $runsRoot ("corrupt-active-run-" + (Get-Date -Format 'yyyyMMdd-HHmmssfff') + '.json')
        }
        Move-Item -LiteralPath $activeRunPath -Destination $staleLock
    }
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null
    $lockRecord = [ordered]@{
        schema = 'codex-weekly-harness-active-run-v1'
        run_id = $RunId
        started_at = (Get-Date).ToString('o')
        caller_cwd = (Get-Location).Path
    }
    $lockTemporary = Join-Path $stateRoot ('active-run.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [System.IO.File]::WriteAllText(
            $lockTemporary,
            ($lockRecord | ConvertTo-Json -Depth 4),
            (New-Object System.Text.UTF8Encoding($false))
        )
        [System.IO.File]::Move($lockTemporary, $activeRunPath)
    } finally {
        if (Test-Path -LiteralPath $lockTemporary -PathType Leaf) {
            Remove-Item -LiteralPath $lockTemporary -Force -ErrorAction SilentlyContinue
        }
    }
    $ownedRunId = $RunId
    $ownedRunDir = $runDir
    $releaseOwnedLock = $true

    $startedAt = Get-Date
    $baseline = Get-MaintainableSnapshot -Root $codexHomePath
    $baselinePath = Join-Path $runDir 'baseline.json'
    Write-JsonFile -Path $baselinePath -Value ([ordered]@{
        schema = 'codex-weekly-harness-baseline-v1'
        run_id = $RunId
        created_at = $startedAt.ToString('o')
        files = $baseline
    })

    $health = [ordered]@{ status = 'skipped'; artifacts = @() }
    if (-not $SkipHealth) {
        try {
            $healthRaw = Invoke-BoundedPowerShellScript `
                -ScriptPath (Join-Path $codexHomePath 'scripts\harness-health.ps1') `
                -Parameters @{ CodexHome = $codexHomePath; SkipEvals = $true } `
                -TimeoutSeconds 180
            $healthResult = $healthRaw | ConvertFrom-Json
            $health = [ordered]@{
                status = [string]$healthResult.status
                artifacts = @($healthResult.artifacts)
            }
        } catch {
            $health = [ordered]@{
                status = 'failed'
                artifacts = @()
                detail = ConvertTo-SafeText -Value $_.Exception.Message -MaxLength 400
            }
        }
    }

    $run = [ordered]@{
        schema = 'codex-weekly-harness-run-v1'
        run_id = $RunId
        phase = 'started'
        started_at = $startedAt.ToString('o')
        lookback_days = $LookbackDays
        max_tasks = $MaxTasks
        window_start = $startedAt.AddDays(-$LookbackDays).ToString('o')
        privacy = [ordered]@{
            summaries_only = $true
            include_outputs = $false
            raw_transcripts_persisted = $false
            raw_task_ids_persisted = $false
        }
        automatic_change_policy = [ordered]@{
            unattended_max_files = 0
            maintenance_enabled = $false
            source_sync_enabled = $false
        }
        health = $health
    }
    Write-JsonFile -Path (Join-Path $runDir 'run.json') -Value $run

    [ordered]@{
        status = if ($health.status -eq 'failed') { 'warning' } else { 'success' }
        summary = 'Weekly harness learning run started.'
        run_id = $RunId
        window_start = $run.window_start
        max_tasks = $MaxTasks
        health = $health
        run_directory = $runDir
        temporary_input_prefix = Join-Path ([System.IO.Path]::GetFullPath($env:TEMP)) ("codex-weekly-input-$RunId-")
        completion_script = Join-Path $codexHomePath 'scripts\invoke-weekly-harness-learning.ps1'
        next_action = 'Collect only recent task summaries and current public research, write a sanitized v1 input file, then call Complete.'
    } | ConvertTo-Json -Depth 8 -Compress
    $releaseOwnedLock = $false
    $ownedRunId = ''
    $ownedRunDir = ''
    exit 0
}

$runRecord = $null
$baselineRecord = $null
$registeredInputPath = ''
$windowStart = [DateTimeOffset]::Now.AddDays(-$LookbackDays)
$windowEnd = [DateTimeOffset]::Now.AddMinutes(5)
if ($Mode -eq 'Complete') {
    if ([string]::IsNullOrWhiteSpace($RunId)) { throw 'Complete requires -RunId from Start.' }
    Assert-ValidRunId -Value $RunId
    $runDir = Join-Path $runsRoot $RunId
    $runPath = Join-Path $runDir 'run.json'
    $baselinePath = Join-Path $runDir 'baseline.json'
    if (-not (Test-Path -LiteralPath $runPath -PathType Leaf) -or -not (Test-Path -LiteralPath $baselinePath -PathType Leaf)) {
        throw "Unknown or incomplete weekly learning run: $RunId"
    }
    $runRecord = Get-Content -LiteralPath $runPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $baselineRecord = Get-Content -LiteralPath $baselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $MaxTasks = [int]$runRecord.max_tasks
    $windowStart = [DateTimeOffset]::Parse([string]$runRecord.window_start)
    $windowEnd = [DateTimeOffset]::Parse([string]$runRecord.started_at).AddMinutes(5)
    if (-not (Test-Path -LiteralPath $activeRunPath -PathType Leaf)) {
        throw 'Active weekly learning lock is missing.'
    }
    $activeRun = Get-Content -LiteralPath $activeRunPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$activeRun.run_id -ne $RunId) {
        throw "Active weekly learning lock belongs to another run: $($activeRun.run_id)"
    }
    if ($activeRun.PSObject.Properties.Name -contains 'input_path') {
        $registeredInputPath = [string]$activeRun.input_path
    }
    $ownedRunId = $RunId
    $ownedRunDir = $runDir
    $releaseOwnedLock = $true
}

if ([string]::IsNullOrWhiteSpace($InputPath) -or -not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    throw 'Complete and DryRun require -InputPath pointing to a sanitized JSON file.'
}
$resolvedInputPath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $InputPath).Path)
$resolvedTempPath = [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
if (-not $resolvedInputPath.StartsWith($resolvedTempPath + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Weekly learning input must be a temporary file under the system TEMP directory.'
}
if ($Mode -eq 'Complete') {
    $expectedPrefix = Join-Path $resolvedTempPath ("codex-weekly-input-$RunId-")
    $ownedInputs = @(Get-ChildItem -LiteralPath $resolvedTempPath -File -Filter ("codex-weekly-input-$RunId-*.json") -ErrorAction SilentlyContinue)
    $inputViolation = ''
    if (-not $resolvedInputPath.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        $inputViolation = 'Weekly learning input does not match the active run prefix.'
    } elseif ([string]::IsNullOrWhiteSpace($registeredInputPath)) {
        $inputViolation = 'Weekly learning input was not registered by the restricted hook.'
    } elseif (-not $resolvedInputPath.Equals([System.IO.Path]::GetFullPath($registeredInputPath), [System.StringComparison]::OrdinalIgnoreCase)) {
        $inputViolation = 'Weekly learning input does not match the path registered by the restricted hook.'
    } elseif ($ownedInputs.Count -ne 1 -or
        -not $ownedInputs[0].FullName.Equals($resolvedInputPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        $inputViolation = 'Weekly learning requires exactly one owned TEMP input file.'
    }
    if ($inputViolation) {
        $cleanupFailures = New-Object System.Collections.Generic.List[string]
        foreach ($ownedInput in $ownedInputs) {
            try {
                Remove-Item -LiteralPath $ownedInput.FullName -Force -ErrorAction Stop
            } catch {
                $cleanupFailures.Add((ConvertTo-SafeText -Value $_.Exception.Message -MaxLength 200)) | Out-Null
            }
        }
        if ($cleanupFailures.Count -gt 0) {
            throw "$inputViolation Cleanup also failed: $($cleanupFailures -join '; ')"
        }
        throw $inputViolation
    }
}
$input = $null
$inputDeleteFailure = ''
try {
    if ((Get-Item -LiteralPath $resolvedInputPath).Length -gt 262144) {
        throw 'Weekly learning input exceeds the 256 KiB limit.'
    }
    $input = Get-Content -LiteralPath $resolvedInputPath -Raw -Encoding UTF8 | ConvertFrom-Json
} finally {
    if (Test-Path -LiteralPath $resolvedInputPath -PathType Leaf) {
        try {
            Remove-Item -LiteralPath $resolvedInputPath -Force -ErrorAction Stop
        } catch {
            $inputDeleteFailure = ConvertTo-SafeText -Value $_.Exception.Message -MaxLength 300
        }
    }
}
if (-not [string]::IsNullOrWhiteSpace($inputDeleteFailure) -or (Test-Path -LiteralPath $resolvedInputPath -PathType Leaf)) {
    throw "Weekly learning could not delete its temporary input after parsing: $inputDeleteFailure"
}
if ((Get-ObjectValue -Object $input -Name 'schema' -Default '') -ne 'codex-weekly-harness-learning-input-v1') {
    throw 'Input schema must be codex-weekly-harness-learning-input-v1.'
}

$existingState = [ordered]@{
    schema = 'codex-weekly-harness-learning-state-v1'
    last_success_at = $null
    last_run_id = $null
    processed_task_hashes = @()
    finding_fingerprints = @()
    research_fingerprints = @()
}
$stateRecovered = $false
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    try {
        $loadedState = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $existingState.processed_task_hashes = @(Get-ObjectValue -Object $loadedState -Name 'processed_task_hashes' -Default @())
        $existingState.finding_fingerprints = @(Get-ObjectValue -Object $loadedState -Name 'finding_fingerprints' -Default @())
        $existingState.research_fingerprints = @(Get-ObjectValue -Object $loadedState -Name 'research_fingerprints' -Default @())
        $existingState.last_success_at = Get-ObjectValue -Object $loadedState -Name 'last_success_at'
        $existingState.last_run_id = Get-ObjectValue -Object $loadedState -Name 'last_run_id'
    } catch {
        $corruptStatePath = Join-Path $stateRoot ('state.corrupt-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff') + '.json')
        Move-Item -LiteralPath $statePath -Destination $corruptStatePath -Force
        $stateRecovered = $true
    }
}

$processedSet = New-Object System.Collections.Generic.HashSet[string]
$findingSet = New-Object System.Collections.Generic.HashSet[string]
$researchSet = New-Object System.Collections.Generic.HashSet[string]
foreach ($value in @($existingState.processed_task_hashes)) { [void]$processedSet.Add([string]$value) }
foreach ($value in @($existingState.finding_fingerprints)) { [void]$findingSet.Add([string]$value) }
foreach ($value in @($existingState.research_fingerprints)) { [void]$researchSet.Add([string]$value) }

$acceptedCategories = @('failure', 'correction', 'test-gap', 'success-pattern', 'tool-failure', 'context-loss', 'process', 'retirement-candidate')
$acceptedRoutes = @('docs', 'eval', 'skill', 'rule', 'script', 'component', 'retire', 'watch')
$newTaskHashes = New-Object System.Collections.Generic.List[string]
$newFindingFingerprints = New-Object System.Collections.Generic.List[string]
$newResearchFingerprints = New-Object System.Collections.Generic.List[string]
$findings = New-Object System.Collections.Generic.List[object]
$research = New-Object System.Collections.Generic.List[object]
$proposals = New-Object System.Collections.Generic.List[object]
$duplicateTasks = 0
$invalidTasks = 0
$outOfWindowTasks = 0
$duplicateFindings = 0
$duplicateResearch = 0
$rejectedResearch = 0

$tasks = @(@((Get-ObjectValue -Object $input -Name 'tasks' -Default @())) | Select-Object -First $MaxTasks)
foreach ($task in $tasks) {
    $sourceRef = [string](Get-ObjectValue -Object $task -Name 'source_ref' -Default '')
    $updatedAt = ConvertTo-SafeText -Value (Get-ObjectValue -Object $task -Name 'updated_at' -Default '') -MaxLength 80
    $taskTimestamp = ConvertTo-TaskTimestamp -Value (Get-ObjectValue -Object $task -Name 'updated_at' -Default '')
    if ([string]::IsNullOrWhiteSpace($sourceRef) -or $sourceRef.Length -gt 2000 -or $null -eq $taskTimestamp) {
        $invalidTasks++
        continue
    }
    if ($taskTimestamp -lt $windowStart -or $taskTimestamp -gt $windowEnd) {
        $outOfWindowTasks++
        continue
    }
    $taskHash = Get-Sha256Text -Text ($sourceRef + '|' + $updatedAt)
    if ($processedSet.Contains($taskHash)) {
        $duplicateTasks++
        continue
    }
    $newTaskHashes.Add($taskHash) | Out-Null

    foreach ($finding in @((Get-ObjectValue -Object $task -Name 'findings' -Default @())) | Select-Object -First 10) {
        $category = (ConvertTo-SafeText -Value (Get-ObjectValue -Object $finding -Name 'category' -Default 'process') -MaxLength 40).ToLowerInvariant()
        if ($category -notin $acceptedCategories) { $category = 'process' }
        $route = (ConvertTo-SafeText -Value (Get-ObjectValue -Object $finding -Name 'route' -Default 'watch') -MaxLength 30).ToLowerInvariant()
        if ($route -notin $acceptedRoutes) { $route = 'watch' }
        $summary = ConvertTo-SafeText -Value (Get-ObjectValue -Object $finding -Name 'summary' -Default '') -MaxLength 700
        if ([string]::IsNullOrWhiteSpace($summary)) { continue }
        $confidenceRaw = Get-ObjectValue -Object $finding -Name 'confidence' -Default 0.5
        try { $confidence = [math]::Max([double]0.0, [math]::Min([double]1.0, [double]$confidenceRaw)) } catch { $confidence = 0.5 }
        $frequency = ConvertTo-SafeText -Value (Get-ObjectValue -Object $finding -Name 'frequency' -Default 'one-off') -MaxLength 40
        $fingerprint = Get-Sha256Text -Text ($category + '|' + $route + '|' + $summary.ToLowerInvariant())
        if ($findingSet.Contains($fingerprint) -or $newFindingFingerprints.Contains($fingerprint)) {
            $duplicateFindings++
            continue
        }
        $evidenceRef = [string](Get-ObjectValue -Object $finding -Name 'evidence_ref' -Default ($sourceRef + '|' + $updatedAt))
        $findings.Add([pscustomobject]@{
            fingerprint = $fingerprint
            category = $category
            route = $route
            summary = $summary
            confidence = [math]::Round($confidence, 2)
            frequency = $frequency
            evidence_hash = Get-Sha256Text -Text $evidenceRef
        }) | Out-Null
        $newFindingFingerprints.Add($fingerprint) | Out-Null
    }
}

foreach ($item in @((Get-ObjectValue -Object $input -Name 'research' -Default @())) | Select-Object -First 8) {
    $title = ConvertTo-SafeText -Value (Get-ObjectValue -Object $item -Name 'title' -Default '') -MaxLength 240
    $sourceType = (ConvertTo-SafeText -Value (Get-ObjectValue -Object $item -Name 'source_type' -Default 'primary') -MaxLength 30).ToLowerInvariant()
    if ($sourceType -notin @('official', 'primary', 'secondary')) { $sourceType = 'secondary' }
    $url = if ($sourceType -eq 'official') {
        ConvertTo-OfficialPublicUrl -Value (Get-ObjectValue -Object $item -Name 'url' -Default '')
    } else { '' }
    $concepts = @(@((Get-ObjectValue -Object $item -Name 'concepts' -Default @()) | ForEach-Object {
        ConvertTo-SafeText -Value $_ -MaxLength 500
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) | Select-Object -First 6)
    if ($sourceType -ne 'official' -or [string]::IsNullOrWhiteSpace($url)) {
        $rejectedResearch++
        continue
    }
    $fingerprint = Get-Sha256Text -Text ($url + '|' + $title.ToLowerInvariant() + '|' + ($concepts -join '|'))
    if ($researchSet.Contains($fingerprint) -or $newResearchFingerprints.Contains($fingerprint)) {
        $duplicateResearch++
        continue
    }
    $research.Add([pscustomobject]@{
        fingerprint = $fingerprint
        title = $title
        url = $url
        source_type = $sourceType
        checked_at = (Get-Date).ToString('o')
        concepts = $concepts
    }) | Out-Null
    $newResearchFingerprints.Add($fingerprint) | Out-Null
}

foreach ($item in @((Get-ObjectValue -Object $input -Name 'proposals' -Default @())) | Select-Object -First 12) {
    $risk = (ConvertTo-SafeText -Value (Get-ObjectValue -Object $item -Name 'risk' -Default 'medium') -MaxLength 20).ToLowerInvariant()
    if ($risk -notin @('low', 'medium', 'high')) { $risk = 'medium' }
    $summaryText = ConvertTo-SafeText -Value (Get-ObjectValue -Object $item -Name 'summary' -Default '') -MaxLength 600
    $rationaleText = ConvertTo-SafeText -Value (Get-ObjectValue -Object $item -Name 'rationale' -Default '') -MaxLength 600
    $proposals.Add([pscustomobject]@{
        id = ConvertTo-SafeText -Value (Get-ObjectValue -Object $item -Name 'id' -Default '') -MaxLength 80
        risk = $risk
        summary_hash = Get-Sha256Text -Text $summaryText
        rationale_hash = Get-Sha256Text -Text $rationaleText
        paths = @(Get-StringArray -Value (Get-ObjectValue -Object $item -Name 'paths' -Default @()) | ForEach-Object {
            ConvertTo-SafeText -Value $_ -MaxLength 220
        })
    }) | Out-Null
}

if ($Mode -eq 'DryRun') {
    [ordered]@{
        status = 'success'
        summary = 'Weekly learning input sanitized and previewed; no state changed.'
        tasks_considered = $tasks.Count
        duplicate_tasks = $duplicateTasks
        invalid_tasks = $invalidTasks
        out_of_window_tasks = $outOfWindowTasks
        new_findings = @($findings | ForEach-Object {
            [pscustomobject]@{
                fingerprint = $_.fingerprint
                category = $_.category
                route = $_.route
                confidence = $_.confidence
                frequency = $_.frequency
                evidence_hash = $_.evidence_hash
            }
        })
        duplicate_findings = $duplicateFindings
        new_research = @($research | ForEach-Object {
            [pscustomobject]@{
                fingerprint = $_.fingerprint
                url = $_.url
                source_type = $_.source_type
                concept_count = @($_.concepts).Count
            }
        })
        duplicate_research = $duplicateResearch
        rejected_research = $rejectedResearch
        proposals = $proposals.ToArray()
        temporary_input_deleted = -not (Test-Path -LiteralPath $resolvedInputPath)
        state_recovered = $stateRecovered
        state_written = $false
    } | ConvertTo-Json -Depth 10 -Compress
    exit 0
}

$currentSnapshot = Get-MaintainableSnapshot -Root $codexHomePath
$changes = @(Compare-Snapshots -Before @($baselineRecord.files) -After $currentSnapshot)
$violations = New-Object System.Collections.Generic.List[string]
foreach ($change in $changes) {
    $violations.Add("Unattended maintainable-file drift detected: $($change.change) $($change.path)") | Out-Null
}

$verification = @()
$syncResult = [ordered]@{
    requested = $false
    status = 'disabled'
    reason = 'Weekly learning is permanently proposal-only; maintenance and source sync use a separate explicit harness lane.'
}
$status = if ($violations.Count -gt 0) { 'blocked' } else { 'success' }

$reportFindings = @($findings | ForEach-Object {
    [pscustomobject]@{
        fingerprint = $_.fingerprint
        category = $_.category
        route = $_.route
        confidence = $_.confidence
        frequency = $_.frequency
        evidence_hash = $_.evidence_hash
    }
})
$reportResearch = @($research | ForEach-Object {
    [pscustomobject]@{
        fingerprint = $_.fingerprint
        url = $_.url
        source_type = $_.source_type
        title_hash = Get-Sha256Text -Text ([string]$_.title)
        concept_hashes = @($_.concepts | ForEach-Object { Get-Sha256Text -Text ([string]$_) })
    }
})

$report = [ordered]@{
    schema = 'codex-weekly-harness-learning-report-v1'
    run_id = $RunId
    status = $status
    started_at = [string]$runRecord.started_at
    completed_at = (Get-Date).ToString('o')
    lookback_days = [int]$runRecord.lookback_days
    max_tasks = [int]$runRecord.max_tasks
    privacy = [ordered]@{
        summaries_only = $true
        raw_transcripts_persisted = $false
        raw_task_ids_persisted = $false
        tool_outputs_persisted = $false
        temporary_input_deleted = -not (Test-Path -LiteralPath $resolvedInputPath)
        only_official_public_urls_persisted = $true
        corrupt_state_recovered = $stateRecovered
    }
    intake = [ordered]@{
        tasks_considered = $tasks.Count
        duplicate_tasks = $duplicateTasks
        invalid_tasks = $invalidTasks
        out_of_window_tasks = $outOfWindowTasks
        new_findings = $findings.Count
        duplicate_findings = $duplicateFindings
        new_research = $research.Count
        duplicate_research = $duplicateResearch
        rejected_research = $rejectedResearch
    }
    findings = $reportFindings
    research = $reportResearch
    proposals = $proposals.ToArray()
    changes = $changes
    violations = $violations.ToArray()
    verification = @($verification)
    sync = $syncResult
}

$reportPath = Join-Path $runDir 'report.json'
$summaryPath = Join-Path $runDir 'summary.md'
Write-JsonFile -Path $reportPath -Value $report

$findingLines = if ($findings.Count -gt 0) {
    ($findings | ForEach-Object { "- [$($_.category)/$($_.route)] finding $($_.fingerprint.Substring(0, 12))" }) -join "`r`n"
} else { '- No new sanitized findings.' }
$researchLines = if ($research.Count -gt 0) {
    ($research | ForEach-Object { "- $($_.source_type): $($_.url)" }) -join "`r`n"
} else { '- No new research items.' }
$changeLines = if ($changes.Count -gt 0) {
    ($changes | ForEach-Object { "- $($_.change): $($_.path)" }) -join "`r`n"
} else { '- No maintainable harness files changed.' }
$violationLines = if ($violations.Count -gt 0) {
    ($violations | ForEach-Object { "- $_" }) -join "`r`n"
} else { '- None.' }

$summary = @"
# Weekly Harness Learning

- Run: $RunId
- Status: $status
- Completed: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
- Tasks considered: $($tasks.Count)
- New findings: $($findings.Count)
- New research items: $($research.Count)
- Raw transcripts persisted: False
- Raw task IDs persisted: False

## Findings

$findingLines

## Research

$researchLines

## Harness Changes

$changeLines

## Policy Violations

$violationLines
"@
Set-Content -LiteralPath $summaryPath -Value $summary -Encoding UTF8

if ($status -eq 'success') {
    $nextState = [ordered]@{
        schema = 'codex-weekly-harness-learning-state-v1'
        last_success_at = (Get-Date).ToString('o')
        last_run_id = $RunId
        processed_task_hashes = @(Merge-UniqueLimited -Existing @($existingState.processed_task_hashes) -New $newTaskHashes.ToArray() -Limit 600)
        finding_fingerprints = @(Merge-UniqueLimited -Existing @($existingState.finding_fingerprints) -New $newFindingFingerprints.ToArray() -Limit 1200)
        research_fingerprints = @(Merge-UniqueLimited -Existing @($existingState.research_fingerprints) -New $newResearchFingerprints.ToArray() -Limit 600)
    }
    Write-JsonFile -Path $statePath -Value $nextState
}

Close-OwnedRunLock -Disposition $(if ($status -eq 'success') { 'completed' } else { 'blocked' })
$releaseOwnedLock = $false
$ownedRunId = ''
$ownedRunDir = ''

$finalResult = [ordered]@{
    status = $status
    summary = 'Weekly harness learning run completed.'
    run_id = $RunId
    findings = $findings.Count
    research_items = $research.Count
    changed_files = $changes.Count
    violations = $violations.ToArray()
    verification = @($verification)
    sync = $syncResult
    state_written = ($status -eq 'success')
    state_recovered = $stateRecovered
    artifacts = @($reportPath, $summaryPath)
}
$finalResult | ConvertTo-Json -Depth 10 -Compress
if ($status -ne 'success') {
    throw "Weekly harness learning completed with status '$status'. Review: $reportPath"
}
} finally {
    if ($releaseOwnedLock) {
        Close-OwnedRunLock -Disposition 'failed'
    }
}
