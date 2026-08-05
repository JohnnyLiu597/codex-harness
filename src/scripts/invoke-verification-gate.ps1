param(
    [string]$ProjectRoot = ".",
    [ValidateSet("DocsOnly", "HarnessOnly", "Runtime", "Full", "BeforeCommit")]
    [string]$Mode = "HarnessOnly",
    [switch]$DocsOnly,
    [switch]$HarnessOnly,
    [switch]$Runtime,
    [switch]$Full,
    [switch]$BeforeCommit,
    [switch]$ContinueOnError,
    [switch]$SkipLint,
    [switch]$SkipBuild,
    [switch]$SkipCargo,
    [string]$BaseRef = "HEAD~1",
    [Alias("TimeoutSeconds")]
    [ValidateRange(1, 86400)]
    [int]$StepTimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"

if ($DocsOnly) { $Mode = "DocsOnly" }
if ($HarnessOnly) { $Mode = "HarnessOnly" }
if ($Runtime) { $Mode = "Runtime" }
if ($Full) { $Mode = "Full" }
if ($BeforeCommit) { $Mode = "BeforeCommit" }

if ($ProjectRoot -eq ".") {
    $scriptProjectRoot = Join-Path $PSScriptRoot ".."
    if ((Test-Path -LiteralPath (Join-Path $scriptProjectRoot "mission.md")) -and
        (Test-Path -LiteralPath (Join-Path $scriptProjectRoot "CONTEXT.md"))) {
        $ProjectRoot = $scriptProjectRoot
    }
}

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$attemptId = [guid]::NewGuid().ToString("N")
$startedAt = Get-Date
$stamp = $startedAt.ToString("yyyyMMdd-HHmmssfff")
$safeMode = $Mode.ToLowerInvariant()
$runId = "$stamp-$safeMode-$($attemptId.Substring(0, 12))"
$runDir = Join-Path $root ("artifacts\verification-gates\" + $runId)
$jsonPath = Join-Path $runDir "verification-gate.json"
$summaryPath = Join-Path $runDir "summary.md"
$steps = New-Object System.Collections.Generic.List[object]
$selection = New-Object System.Collections.Generic.List[object]
$stepResults = @{}
$testSurface = $null
$surfaceCandidates = @()
$fatalError = $null

New-Item -ItemType Directory -Force -Path $runDir | Out-Null

function ConvertTo-Slug {
    param([string]$Value)

    $slug = (([string]$Value).ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ($slug) { return $slug }
    return "verification"
}

function Get-Sha256Text {
    param([AllowEmptyString()][string]$Text)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Text)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function ConvertTo-SafeText {
    param(
        [AllowEmptyString()][string]$Text,
        [int]$MaxLength = 240
    )

    $value = [string]$Text
    if ($root) {
        $value = $value.Replace($root, "<project>")
        $value = $value.Replace(($root -replace '\\', '/'), "<project>")
    }
    $value = ($value -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '').Trim()
    if ($value.Length -gt $MaxLength) { return $value.Substring(0, $MaxLength) }
    return $value
}

function ConvertTo-PowerShellLiteral {
    param([object]$Value)

    if ($null -eq $Value) { return '$null' }
    if ($Value -is [System.Management.Automation.SwitchParameter]) {
        return $(if ([bool]$Value) { '$true' } else { '$false' })
    }
    if ($Value -is [bool]) { return $(if ($Value) { '$true' } else { '$false' }) }
    if ($Value -is [string]) { return "'" + $Value.Replace("'", "''") + "'" }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $items = @($Value | ForEach-Object { ConvertTo-PowerShellLiteral -Value $_ })
        return "@(" + ($items -join ", ") + ")"
    }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
        return [Convert]::ToString($Value, [Globalization.CultureInfo]::InvariantCulture)
    }
    return "'" + ([string]$Value).Replace("'", "''") + "'"
}

function ConvertTo-NativeArgument {
    param([AllowEmptyString()][string]$Value)

    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }

    $builder = New-Object System.Text.StringBuilder
    $builder.Append('"') | Out-Null
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq [char]92) {
            $backslashes++
            continue
        }
        if ($character -eq [char]34) {
            if ($backslashes -gt 0) { $builder.Append(('\' * ($backslashes * 2))) | Out-Null }
            $builder.Append('\"') | Out-Null
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) {
            $builder.Append(('\' * $backslashes)) | Out-Null
            $backslashes = 0
        }
        $builder.Append($character) | Out-Null
    }
    if ($backslashes -gt 0) { $builder.Append(('\' * ($backslashes * 2))) | Out-Null }
    $builder.Append('"') | Out-Null
    return $builder.ToString()
}

function New-PowerShellFileArguments {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [hashtable]$Parameters = @{}
    )

    $arguments = New-Object System.Collections.Generic.List[string]
    foreach ($fixed in @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File')) {
        $arguments.Add($fixed) | Out-Null
    }
    $arguments.Add((ConvertTo-NativeArgument -Value $ScriptPath)) | Out-Null

    foreach ($key in @($Parameters.Keys | Sort-Object)) {
        if ([string]$key -notmatch '^[A-Za-z][A-Za-z0-9_]*$') {
            throw "Unsupported verification script parameter name: $key"
        }
        $value = $Parameters[$key]
        if ($value -is [System.Management.Automation.SwitchParameter] -or $value -is [bool]) {
            if ([bool]$value) { $arguments.Add("-$key") | Out-Null }
            continue
        }
        if ($null -eq $value) { continue }

        $values = if ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) { @($value) } else { @($value) }
        if ($values.Count -eq 0) { continue }
        $arguments.Add("-$key") | Out-Null
        foreach ($item in $values) {
            $textValue = if ($item -is [IFormattable]) {
                $item.ToString($null, [Globalization.CultureInfo]::InvariantCulture)
            } else {
                [string]$item
            }
            $arguments.Add((ConvertTo-NativeArgument -Value $textValue)) | Out-Null
        }
    }
    return ($arguments -join ' ')
}

function New-ScriptInvocationCommand {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [hashtable]$Parameters = @{}
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('$ErrorActionPreference = "Stop"') | Out-Null
    $lines.Add('$invokeParameters = @{}') | Out-Null
    foreach ($key in @($Parameters.Keys | Sort-Object)) {
        $keyLiteral = ConvertTo-PowerShellLiteral -Value ([string]$key)
        $valueLiteral = ConvertTo-PowerShellLiteral -Value $Parameters[$key]
        $lines.Add("`$invokeParameters[$keyLiteral] = $valueLiteral") | Out-Null
    }
    $pathLiteral = ConvertTo-PowerShellLiteral -Value $ScriptPath
    $lines.Add("& $pathLiteral @invokeParameters") | Out-Null
    return ($lines -join "`r`n")
}

function Test-IsWindows {
    try {
        return [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
    } catch {
        return ($env:OS -eq "Windows_NT")
    }
}

function Get-DescendantProcessIds {
    param([int]$ParentId)

    $descendants = New-Object System.Collections.Generic.List[int]
    try {
        $processes = @(Get-CimInstance Win32_Process -ErrorAction Stop | Select-Object ProcessId, ParentProcessId)
        $pending = New-Object System.Collections.Generic.Queue[int]
        $seen = @{}
        $pending.Enqueue($ParentId)
        $seen[$ParentId] = $true
        while ($pending.Count -gt 0) {
            $currentId = $pending.Dequeue()
            foreach ($candidate in @($processes | Where-Object { [int]$_.ParentProcessId -eq $currentId })) {
                $childId = [int]$candidate.ProcessId
                if ($seen.ContainsKey($childId)) { continue }
                $seen[$childId] = $true
                $descendants.Add($childId) | Out-Null
                $pending.Enqueue($childId)
            }
        }
    } catch { }
    return $descendants.ToArray()
}

function Stop-ProcessTree {
    param([System.Diagnostics.Process]$Process)

    if ($null -eq $Process) { return }
    try { $rootProcessId = [int]$Process.Id } catch { return }
    $descendantIds = @(Get-DescendantProcessIds -ParentId $rootProcessId)

    if (Test-IsWindows) {
        $taskkill = Get-Command taskkill.exe -ErrorAction SilentlyContinue
        if ($taskkill) {
            try { & $taskkill.Source /PID $rootProcessId /T /F 2>$null | Out-Null } catch { }
            foreach ($childId in $descendantIds) {
                try { & $taskkill.Source /PID $childId /T /F 2>$null | Out-Null } catch { }
            }
        }
    }

    foreach ($childId in @($descendantIds | Sort-Object -Descending)) {
        $child = $null
        try {
            $child = [System.Diagnostics.Process]::GetProcessById($childId)
            if (-not $child.HasExited) { $child.Kill() }
            $child.WaitForExit(5000) | Out-Null
        } catch { }
        if ($child) { try { $child.Dispose() } catch { } }
    }

    try {
        if (-not $Process.HasExited) {
            $killTreeMethod = $Process.GetType().GetMethod("Kill", [type[]]@([bool]))
            if ($killTreeMethod) {
                $killTreeMethod.Invoke($Process, @($true)) | Out-Null
            } else {
                $Process.Kill()
            }
        }
    } catch { }
    try { $Process.WaitForExit(5000) | Out-Null } catch { }
}

function Get-LineCount {
    param([AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return 0 }
    return @($Text -split "`r?`n").Count
}

function Invoke-PowerShellCapture {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string]$LogPath,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds,
        [switch]$HonorLastExitCode,
        [string]$ScriptPath = "",
        [hashtable]$ScriptParameters = @{}
    )

    $captureId = [guid]::NewGuid().ToString("N")
    $tempDir = Join-Path ([IO.Path]::GetTempPath()) ("codex-verification-gate-" + $attemptId + "-" + $captureId)
    $runnerPath = Join-Path $tempDir "runner.ps1"
    $process = $null
    $stdoutTask = $null
    $stderrTask = $null
    $stdout = ""
    $stderr = ""
    $exitCode = -1
    $timedOut = $false
    $launchFailed = $false
    $stepStarted = Get-Date

    $useScriptProcess = -not [string]::IsNullOrWhiteSpace($ScriptPath)
    $honorNative = if ($HonorLastExitCode) { '$true' } else { '$false' }
    $runner = @"
`$ErrorActionPreference = 'Stop'
try {
    `$global:LASTEXITCODE = 0
$Command
    `$invocationSucceeded = `$?
    `$nativeExitCode = `$LASTEXITCODE
    if ($honorNative -and `$null -ne `$nativeExitCode -and [int]`$nativeExitCode -ne 0) { exit [int]`$nativeExitCode }
    if (-not `$invocationSucceeded) { exit 1 }
    exit 0
} catch {
    [Console]::Error.WriteLine(`$_.Exception.Message)
    exit 1
}
"@

    try {
        try {
            $startInfo = New-Object System.Diagnostics.ProcessStartInfo
            $startInfo.FileName = "powershell.exe"
            if ($useScriptProcess) {
                $startInfo.Arguments = New-PowerShellFileArguments -ScriptPath $ScriptPath -Parameters $ScriptParameters
            } else {
                New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
                Set-Content -LiteralPath $runnerPath -Value $runner -Encoding UTF8
                $startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$runnerPath`""
            }
            $startInfo.WorkingDirectory = $root
            $startInfo.UseShellExecute = $false
            $startInfo.CreateNoWindow = $true
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true

            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $startInfo
            if (-not $process.Start()) { throw "PowerShell verification process did not start." }
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()
        } catch {
            $launchFailed = $true
            $stderr = $_.Exception.Message
            if ($process) { try { $process.Dispose() } catch { } }
            $process = $null
        }

        if ($process) {
            if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
                $timedOut = $true
                Stop-ProcessTree -Process $process
                $exitCode = 124
            } else {
                $process.WaitForExit()
                $process.Refresh()
                $exitCode = [int]$process.ExitCode
            }
        }
    } finally {
        if ($process) {
            try {
                if (-not $process.HasExited) { Stop-ProcessTree -Process $process }
            } catch { }
        }
        if ($stdoutTask) {
            try {
                if ($stdoutTask.Wait(5000)) { $stdout = [string]$stdoutTask.Result }
                else { $stderr += "`nTimed out while draining captured stdout." }
            } catch {
                $stderr += "`nUnable to read captured stdout."
            }
        }
        if ($stderrTask) {
            try {
                $capturedError = if ($stderrTask.Wait(5000)) { [string]$stderrTask.Result } else { "Timed out while draining captured stderr." }
                if ($capturedError) { $stderr = (($stderr, $capturedError) -ne "") -join "`n" }
            } catch { $stderr += "`nUnable to read captured stderr." }
        }

        $logParts = New-Object System.Collections.Generic.List[string]
        if ($stdout) { $logParts.Add($stdout.TrimEnd()) | Out-Null }
        if ($stderr) { $logParts.Add("[stderr]`r`n" + $stderr.TrimEnd()) | Out-Null }
        if ($timedOut) { $logParts.Add("[gate] Step timed out after $TimeoutSeconds second(s).") | Out-Null }
        if ($launchFailed) { $logParts.Add("[gate] Process launch failed.") | Out-Null }
        Set-Content -LiteralPath $LogPath -Value ($logParts -join "`r`n") -Encoding UTF8

        if ($process) { try { $process.Dispose() } catch { } }
        if (Test-Path -LiteralPath $runnerPath) {
            Remove-Item -LiteralPath $runnerPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $tempDir) {
            Remove-Item -LiteralPath $tempDir -Force -ErrorAction SilentlyContinue
        }
    }

    return [pscustomobject]@{
        stdout = $stdout
        stderr = $stderr
        exit_code = $exitCode
        timed_out = $timedOut
        launch_failed = $launchFailed
        duration_ms = [int]((Get-Date) - $stepStarted).TotalMilliseconds
    }
}

function Resolve-ProjectScript {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [switch]$GlobalFallback
    )

    $projectScript = Join-Path $root "scripts\$Name"
    if (Test-Path -LiteralPath $projectScript -PathType Leaf) {
        return [pscustomobject]@{ path = $projectScript; scope = "project"; source = "scripts\$Name" }
    }

    if ($GlobalFallback) {
        $globalScript = Join-Path "$env:USERPROFILE\.codex\scripts" $Name
        if (Test-Path -LiteralPath $globalScript -PathType Leaf) {
            return [pscustomobject]@{ path = $globalScript; scope = "global"; source = "codex-home/scripts/$Name" }
        }
    }

    return $null
}

function Add-MissingStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [ValidateSet("required", "optional")][string]$Requirement,
        [string]$Origin,
        [string]$Source,
        [bool]$VerificationCheck
    )

    $index = $steps.Count + 1
    $safeName = ConvertTo-Slug -Value $Name
    $logName = ("{0:D2}-{1}.log" -f $index, $safeName)
    $logPath = Join-Path $runDir $logName
    $status = if ($Requirement -eq "required") { "failed" } else { "skipped" }
    Set-Content -LiteralPath $logPath -Value ("Script not found: " + $Source) -Encoding UTF8
    $record = [pscustomobject]@{
        name = $Name
        status = $status
        requirement = $Requirement
        origin = $Origin
        verification_check = $VerificationCheck
        output_contract = "structured"
        execution = "missing"
        failure_code = if ($Requirement -eq "required") { "required-script-missing" } else { "optional-script-missing" }
        duration_ms = 0
        timeout_seconds = $StepTimeoutSeconds
        timed_out = $false
        exit_code = $null
        source = ConvertTo-SafeText -Text $Source
        log = $logName
        stdout_sha256 = Get-Sha256Text -Text ""
        stderr_sha256 = Get-Sha256Text -Text ""
        stdout_lines = 0
        stderr_lines = 0
        result_schema = ""
        result_status = ""
    }
    $steps.Add($record) | Out-Null
    $result = [pscustomobject]@{ record = $record; parsed = $null }
    $stepResults[$Name] = $result

    if ($status -eq "failed" -and -not $ContinueOnError) {
        throw "Required verification step is unavailable: $Name"
    }
    return $result
}

function Invoke-GateStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Command,
        [ValidateSet("required", "optional")][string]$Requirement = "required",
        [ValidateSet("structured", "unstructured")][string]$OutputContract = "structured",
        [string]$ExpectedSchema = "",
        [string]$Origin = "gate",
        [string]$Source = "",
        [bool]$VerificationCheck = $true,
        [switch]$HonorLastExitCode,
        [string]$ScriptPath = "",
        [hashtable]$ScriptParameters = @{}
    )

    if ($stepResults.ContainsKey($Name)) { return $stepResults[$Name] }

    $index = $steps.Count + 1
    $safeName = ConvertTo-Slug -Value $Name
    $logName = ("{0:D2}-{1}.log" -f $index, $safeName)
    $logPath = Join-Path $runDir $logName
    $capture = Invoke-PowerShellCapture -Command $Command -LogPath $logPath -TimeoutSeconds $StepTimeoutSeconds -HonorLastExitCode:$HonorLastExitCode -ScriptPath $ScriptPath -ScriptParameters $ScriptParameters
    $status = "failed"
    $failureCode = ""
    $parsed = $null
    $resultSchema = ""
    $resultStatus = ""

    if ($capture.timed_out) {
        $failureCode = "timeout"
    } elseif ($capture.launch_failed) {
        $failureCode = "process-launch"
    } elseif ($capture.exit_code -ne 0) {
        $failureCode = "process-exit"
    } elseif ($OutputContract -eq "unstructured") {
        $status = "passed"
    } elseif ([string]::IsNullOrWhiteSpace($capture.stdout)) {
        $failureCode = "blank-structured-output"
    } else {
        try {
            $parsed = $capture.stdout | ConvertFrom-Json -ErrorAction Stop
            $statusProperty = $parsed.PSObject.Properties["status"]
            if (-not $statusProperty) {
                $failureCode = "missing-status"
            } else {
                $resultStatus = ([string]$parsed.status).Trim().ToLowerInvariant()
                $schemaProperty = $parsed.PSObject.Properties["schema"]
                if ($schemaProperty) { $resultSchema = ConvertTo-SafeText -Text ([string]$parsed.schema) }
                if ($ExpectedSchema -and $resultSchema -ne $ExpectedSchema) {
                    $failureCode = "unexpected-schema"
                } else {
                    switch ($resultStatus) {
                        { $_ -in @("success", "passed", "pass", "ok") } { $status = "passed"; break }
                        { $_ -in @("warning", "warn") } { $status = "warning"; break }
                        "skipped" {
                            if ($Requirement -eq "optional") { $status = "skipped" } else { $failureCode = "required-step-skipped" }
                            break
                        }
                        { $_ -in @("failed", "failure", "error") } { $failureCode = "reported-failure"; break }
                        default { $failureCode = "unknown-status" }
                    }
                }
            }
        } catch {
            $failureCode = "invalid-json"
        }
    }

    $record = [pscustomobject]@{
        name = $Name
        status = $status
        requirement = $Requirement
        origin = $Origin
        verification_check = $VerificationCheck
        output_contract = $OutputContract
        execution = "ran"
        failure_code = $failureCode
        duration_ms = $capture.duration_ms
        timeout_seconds = $StepTimeoutSeconds
        timed_out = [bool]$capture.timed_out
        exit_code = $capture.exit_code
        source = ConvertTo-SafeText -Text $Source
        log = $logName
        stdout_sha256 = Get-Sha256Text -Text $capture.stdout
        stderr_sha256 = Get-Sha256Text -Text $capture.stderr
        stdout_lines = Get-LineCount -Text $capture.stdout
        stderr_lines = Get-LineCount -Text $capture.stderr
        result_schema = $resultSchema
        result_status = $resultStatus
    }
    $steps.Add($record) | Out-Null
    $result = [pscustomobject]@{ record = $record; parsed = $parsed }
    $stepResults[$Name] = $result

    if ($status -eq "failed" -and -not $ContinueOnError) {
        throw "Verification gate failed at $Name."
    }
    return $result
}

function Invoke-ScriptStep {
    param(
        [Parameter(Mandatory = $true)][string]$StepName,
        [Parameter(Mandatory = $true)][string]$ScriptName,
        [hashtable]$Parameters = @{},
        [switch]$GlobalFallback,
        [ValidateSet("required", "optional")][string]$Requirement = "required",
        [string]$ExpectedSchema = "",
        [string]$Origin = "gate",
        [bool]$VerificationCheck = $true
    )

    if ($stepResults.ContainsKey($StepName)) { return $stepResults[$StepName] }
    $resolved = Resolve-ProjectScript -Name $ScriptName -GlobalFallback:$GlobalFallback
    if (-not $resolved) {
        return Add-MissingStep -Name $StepName -Requirement $Requirement -Origin $Origin -Source ("scripts/" + $ScriptName) -VerificationCheck $VerificationCheck
    }

    $effectiveParameters = @{}
    foreach ($key in $Parameters.Keys) { $effectiveParameters[$key] = $Parameters[$key] }
    $command = New-ScriptInvocationCommand -ScriptPath $resolved.path -Parameters $effectiveParameters
    return Invoke-GateStep -Name $StepName -Command $command -Requirement $Requirement -OutputContract "structured" -ExpectedSchema $ExpectedSchema -Origin $Origin -Source $resolved.source -VerificationCheck $VerificationCheck -HonorLastExitCode -ScriptPath $resolved.path -ScriptParameters $effectiveParameters
}

function Invoke-GitText {
    param([string[]]$Arguments)

    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) { return $null }
    try {
        $global:LASTEXITCODE = 0
        $output = @(& $git.Source -C $root @Arguments 2>$null)
        if ($LASTEXITCODE -ne 0) { return $null }
        return (($output | ForEach-Object { [string]$_ }) -join "`n").TrimEnd()
    } catch {
        return $null
    }
}

function Get-GitSnapshot {
    $inside = Invoke-GitText -Arguments @("rev-parse", "--is-inside-work-tree")
    if ($inside -ne "true") {
        return [ordered]@{
            available = $false
            branch = ""
            head = ""
            base_ref = ConvertTo-SafeText -Text $BaseRef
            base_commit = ""
            diff = [ordered]@{ sha256 = Get-Sha256Text -Text ""; bytes = 0; changed_files = 0 }
            worktree = [ordered]@{ sha256 = Get-Sha256Text -Text ""; entries = 0 }
        }
    }

    $head = Invoke-GitText -Arguments @("rev-parse", "HEAD")
    $branch = Invoke-GitText -Arguments @("branch", "--show-current")
    $baseCommit = ""
    if ($BaseRef.Length -le 200 -and $BaseRef -match '^[A-Za-z0-9._/@~^:+-]+$') {
        $baseCommit = [string](Invoke-GitText -Arguments @("rev-parse", "--verify", "$BaseRef^{commit}"))
    }
    $diffText = ""
    $nameStatus = ""
    if ($baseCommit) {
        $diffValue = Invoke-GitText -Arguments @("diff", "--no-ext-diff", "--binary", $baseCommit, "--")
        $nameValue = Invoke-GitText -Arguments @("diff", "--no-ext-diff", "--name-status", $baseCommit, "--")
        if ($null -ne $diffValue) { $diffText = [string]$diffValue }
        if ($null -ne $nameValue) { $nameStatus = [string]$nameValue }
    }
    $statusText = [string](Invoke-GitText -Arguments @("status", "--porcelain=v1"))
    return [ordered]@{
        available = $true
        branch = ConvertTo-SafeText -Text $branch
        head = [string]$head
        base_ref = ConvertTo-SafeText -Text $BaseRef
        base_commit = $baseCommit
        diff = [ordered]@{
            sha256 = Get-Sha256Text -Text $diffText
            bytes = [Text.Encoding]::UTF8.GetByteCount($diffText)
            changed_files = if ($nameStatus) { @($nameStatus -split "`r?`n").Count } else { 0 }
        }
        worktree = [ordered]@{
            sha256 = Get-Sha256Text -Text $statusText
            entries = if ($statusText) { @($statusText -split "`r?`n").Count } else { 0 }
        }
    }
}

function Get-ApplicationVersion {
    param([string]$Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) { return $null }
    $version = ""
    try { $version = [string]$command.FileVersionInfo.ProductVersion } catch { }
    if (-not $version) {
        try { $version = [string]$command.Version } catch { }
    }
    if (-not $version) { $version = "present" }
    return ConvertTo-SafeText -Text $version -MaxLength 120
}

function Get-ToolVersions {
    $gitVersion = ""
    try {
        $gitCommand = Get-Command git -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($gitCommand) { $gitVersion = [string](& $gitCommand.Source --version 2>$null | Select-Object -First 1) }
    } catch { }
    return [ordered]@{
        powershell = $PSVersionTable.PSVersion.ToString()
        git = if ($gitVersion) { ConvertTo-SafeText -Text $gitVersion -MaxLength 120 } else { $null }
        pwsh = Get-ApplicationVersion -Name "pwsh"
        node = Get-ApplicationVersion -Name "node"
        npm = Get-ApplicationVersion -Name "npm"
        python = Get-ApplicationVersion -Name "python"
        dotnet = Get-ApplicationVersion -Name "dotnet"
        cargo = Get-ApplicationVersion -Name "cargo"
        go = Get-ApplicationVersion -Name "go"
        rg = Get-ApplicationVersion -Name "rg"
    }
}

function Get-TestSurfaceCandidates {
    param([object]$Surface)

    if ($null -eq $Surface -or -not $Surface.recommended) { return @() }
    $items = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($lane in @("quick", "runtime")) {
        foreach ($candidate in @($Surface.recommended.$lane)) {
            $commandText = [string]$candidate.command
            if ([string]::IsNullOrWhiteSpace($commandText)) { continue }
            $commandHash = Get-Sha256Text -Text $commandText
            $key = (([string]$candidate.kind).ToLowerInvariant() + "|" + $commandHash)
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            $items.Add([pscustomobject]@{
                id = $commandHash.Substring(0, 12)
                lane = $lane
                kind = ([string]$candidate.kind).ToLowerInvariant()
                command = $commandText
                command_sha256 = $commandHash
                source = ConvertTo-SafeText -Text ([string]$candidate.source)
                priority = [int]$candidate.priority
            }) | Out-Null
        }
    }
    return $items.ToArray()
}

function Add-SurfaceSelection {
    param(
        [Parameter(Mandatory = $true)][object]$Candidate,
        [Parameter(Mandatory = $true)][string]$Disposition,
        [Parameter(Mandatory = $true)][string]$Reason,
        [string]$GateStep = ""
    )

    $item = [pscustomobject]@{
        id = $Candidate.id
        lane = $Candidate.lane
        kind = $Candidate.kind
        source = $Candidate.source
        command_sha256 = $Candidate.command_sha256
        disposition = $Disposition
        reason = $Reason
        gate_step = $GateStep
    }
    $selection.Add($item) | Out-Null
    return $item
}

function Test-CandidateSkipped {
    param([object]$Candidate)

    if ($SkipLint -and $Candidate.kind -eq "lint") { return "skip-lint-requested" }
    if ($SkipBuild -and $Candidate.kind -eq "build") { return "skip-build-requested" }
    if ($SkipCargo -and ($Candidate.source -match '(?i)cargo\.toml' -or $Candidate.command -match '(?i)(^|[\s&;])cargo(?:\.exe)?\s')) {
        return "skip-cargo-requested"
    }
    return ""
}

function Record-FixedModeSelection {
    param([string]$SelectedMode)

    $sourceToStep = @{
        "scripts/verify-harness.ps1" = "harness-verify"
        "scripts\verify-harness.ps1" = "harness-verify"
        "scripts/check-features.ps1" = "feature-list"
        "scripts\check-features.ps1" = "feature-list"
        "scripts/check-architecture.ps1" = "architecture-check"
        "scripts\check-architecture.ps1" = "architecture-check"
        "scripts/check-tool-evals.ps1" = "tool-evals"
        "scripts\check-tool-evals.ps1" = "tool-evals"
    }
    foreach ($candidate in $surfaceCandidates) {
        $mappedStep = ""
        if ($sourceToStep.ContainsKey($candidate.source)) { $mappedStep = $sourceToStep[$candidate.source] }
        if ($mappedStep -and $stepResults.ContainsKey($mappedStep)) {
            Add-SurfaceSelection -Candidate $candidate -Disposition "covered" -Reason "covered-by-mode-step" -GateStep $mappedStep | Out-Null
        } else {
            Add-SurfaceSelection -Candidate $candidate -Disposition "excluded" -Reason ("mode-" + $SelectedMode.ToLowerInvariant() + "-does-not-run-this-surface") | Out-Null
        }
    }
}

function Invoke-TestSurfaceDetection {
    $resolved = Resolve-ProjectScript -Name "detect-project-test-surface.ps1" -GlobalFallback
    if (-not $resolved) {
        return Add-MissingStep -Name "test-surface-detection" -Requirement "required" -Origin "test-surface-detection" -Source "scripts/detect-project-test-surface.ps1" -VerificationCheck $false
    }
    $parameters = @{}
    if ($resolved.scope -eq "global") { $parameters.ProjectRoot = $root }
    $command = New-ScriptInvocationCommand -ScriptPath $resolved.path -Parameters $parameters
    return Invoke-GateStep -Name "test-surface-detection" -Command $command -Requirement "required" -OutputContract "structured" -ExpectedSchema "codex-project-test-surface-v1" -Origin "test-surface-detection" -Source $resolved.source -VerificationCheck $false -HonorLastExitCode -ScriptPath $resolved.path -ScriptParameters $parameters
}

function Invoke-DocsGate {
    $resolvedDocs = Resolve-ProjectScript -Name "check-project-docs.ps1" -GlobalFallback
    if (-not $resolvedDocs) {
        Add-MissingStep -Name "docs-sync" -Requirement "required" -Origin "gate" -Source "scripts/check-project-docs.ps1" -VerificationCheck $true | Out-Null
    } else {
        $parameters = @{ BaseRef = $BaseRef }
        if ($resolvedDocs.scope -eq "global") { $parameters.ProjectRoot = $root }
        $command = New-ScriptInvocationCommand -ScriptPath $resolvedDocs.path -Parameters $parameters
        Invoke-GateStep -Name "docs-sync" -Command $command -Requirement "required" -OutputContract "structured" -Origin "gate" -Source $resolvedDocs.source -VerificationCheck $true -HonorLastExitCode -ScriptPath $resolvedDocs.path -ScriptParameters $parameters | Out-Null
    }
    Invoke-ScriptStep -StepName "feature-list" -ScriptName "check-features.ps1" -Requirement "required" | Out-Null
    Invoke-ScriptStep -StepName "architecture-check" -ScriptName "check-architecture.ps1" -Requirement "optional" | Out-Null
}

function Invoke-HarnessGate {
    Invoke-ScriptStep -StepName "harness-verify" -ScriptName "verify-harness.ps1" -Requirement "required" | Out-Null
    $audit = Resolve-ProjectScript -Name "audit-project-harness.ps1" -GlobalFallback
    if (-not $audit) {
        Add-MissingStep -Name "project-harness-audit" -Requirement "required" -Origin "gate" -Source "scripts/audit-project-harness.ps1" -VerificationCheck $true | Out-Null
    } else {
        $parameters = @{}
        if ($audit.scope -eq "global") { $parameters.ProjectRoot = $root }
        $command = New-ScriptInvocationCommand -ScriptPath $audit.path -Parameters $parameters
        Invoke-GateStep -Name "project-harness-audit" -Command $command -Requirement "required" -OutputContract "structured" -Origin "gate" -Source $audit.source -VerificationCheck $true -HonorLastExitCode -ScriptPath $audit.path -ScriptParameters $parameters | Out-Null
    }
    Invoke-ScriptStep -StepName "context-budget-audit" -ScriptName "audit-context-budget.ps1" -Requirement "required" | Out-Null
    Invoke-ScriptStep -StepName "component-registry-audit" -ScriptName "audit-harness-components.ps1" -Requirement "required" | Out-Null
    Invoke-ScriptStep -StepName "feature-list" -ScriptName "check-features.ps1" -Requirement "required" | Out-Null
    Invoke-ScriptStep -StepName "tool-evals" -ScriptName "check-tool-evals.ps1" -Requirement "required" | Out-Null
    Invoke-ScriptStep -StepName "architecture-check" -ScriptName "check-architecture.ps1" -Requirement "optional" | Out-Null
    Invoke-ScriptStep -StepName "trace-evals-dry-run" -ScriptName "run-codex-trace-evals.ps1" -Parameters @{ DryRun = $true } -Requirement "optional" | Out-Null
}

function Invoke-SurfaceDrivenGate {
    param([switch]$FullMode)

    $checkAll = Resolve-ProjectScript -Name "check-all.ps1"
    if ($checkAll) {
        $parameters = if ($FullMode) { @{ Full = $true } } else { @{ Runtime = $true; Smoke = $true; TraceEvals = $true } }
        if ($SkipLint) { $parameters.SkipLint = $true }
        if ($SkipBuild) { $parameters.SkipBuild = $true }
        if ($SkipCargo) { $parameters.SkipCargo = $true }
        if ($ContinueOnError) { $parameters.ContinueOnError = $true }
        $stepName = if ($FullMode) { "check-all-full" } else { "check-all-runtime" }
        $command = New-ScriptInvocationCommand -ScriptPath $checkAll.path -Parameters $parameters
        Invoke-GateStep -Name $stepName -Command $command -Requirement "required" -OutputContract "structured" -Origin "gate" -Source $checkAll.source -VerificationCheck $true -HonorLastExitCode -ScriptPath $checkAll.path -ScriptParameters $parameters | Out-Null
        foreach ($candidate in $surfaceCandidates) {
            $skipReason = Test-CandidateSkipped -Candidate $candidate
            if ($skipReason) {
                Add-SurfaceSelection -Candidate $candidate -Disposition "excluded" -Reason $skipReason | Out-Null
            } elseif ($candidate.kind -in @("runtime", "verification-gate")) {
                Add-SurfaceSelection -Candidate $candidate -Disposition "excluded" -Reason "unsafe-or-recursive-for-automatic-gate" | Out-Null
            } else {
                Add-SurfaceSelection -Candidate $candidate -Disposition "covered" -Reason "covered-by-check-all" -GateStep $stepName | Out-Null
            }
        }
        return
    }

    $allowedKinds = @("package-verify", "harness-verify", "build", "typecheck", "lint", "unit-test", "smoke", "e2e")
    if ($FullMode) { $allowedKinds += "coverage" }
    $selectedCount = 0
    $ordinal = 0
    foreach ($candidate in $surfaceCandidates) {
        $ordinal++
        $skipReason = Test-CandidateSkipped -Candidate $candidate
        if ($skipReason) {
            Add-SurfaceSelection -Candidate $candidate -Disposition "excluded" -Reason $skipReason | Out-Null
            continue
        }
        if ($candidate.kind -in @("runtime", "verification-gate", "full-gate")) {
            Add-SurfaceSelection -Candidate $candidate -Disposition "excluded" -Reason "unsafe-or-recursive-for-automatic-gate" | Out-Null
            continue
        }
        if ($candidate.kind -notin $allowedKinds) {
            Add-SurfaceSelection -Candidate $candidate -Disposition "excluded" -Reason "unsupported-test-surface-kind" | Out-Null
            continue
        }

        $stepName = "surface-$($candidate.kind)-$ordinal"
        $selectionItem = Add-SurfaceSelection -Candidate $candidate -Disposition "executed" -Reason "selected-from-test-surface" -GateStep $stepName
        $result = Invoke-GateStep -Name $stepName -Command $candidate.command -Requirement "required" -OutputContract "unstructured" -Origin "test-surface" -Source $candidate.source -VerificationCheck $true -HonorLastExitCode
        if ($result.record.status -eq "failed") { $selectionItem.disposition = "failed" }
        $selectedCount++
    }

    if ($selectedCount -eq 0) {
        Add-MissingStep -Name "runtime-verification-selection" -Requirement "required" -Origin "test-surface" -Source "detected-test-surface" -VerificationCheck $true | Out-Null
        $stepResults["runtime-verification-selection"].record.failure_code = "zero-required-verification-selection"
    }
}

try {
    $surfaceResult = Invoke-TestSurfaceDetection
    if ($surfaceResult.parsed) {
        $testSurface = $surfaceResult.parsed
        $surfaceCandidates = @(Get-TestSurfaceCandidates -Surface $testSurface)
    }

    switch ($Mode) {
        "DocsOnly" {
            Invoke-DocsGate
            Record-FixedModeSelection -SelectedMode $Mode
        }
        "HarnessOnly" {
            Invoke-HarnessGate
            Record-FixedModeSelection -SelectedMode $Mode
        }
        "Runtime" {
            Invoke-SurfaceDrivenGate
        }
        "Full" {
            Invoke-SurfaceDrivenGate -FullMode
        }
        "BeforeCommit" {
            Invoke-DocsGate
            Invoke-HarnessGate
            Record-FixedModeSelection -SelectedMode $Mode
        }
    }
} catch {
    $fatalError = $_
}

if ($fatalError -and @($steps | Where-Object { $_.status -eq "failed" }).Count -eq 0) {
    $index = $steps.Count + 1
    $logName = ("{0:D2}-gate-internal.log" -f $index)
    Set-Content -LiteralPath (Join-Path $runDir $logName) -Value $fatalError.Exception.Message -Encoding UTF8
    $steps.Add([pscustomobject]@{
        name = "gate-internal"
        status = "failed"
        requirement = "required"
        origin = "gate"
        verification_check = $true
        output_contract = "structured"
        execution = "failed-before-run"
        failure_code = "internal-error"
        duration_ms = 0
        timeout_seconds = $StepTimeoutSeconds
        timed_out = $false
        exit_code = $null
        source = "invoke-verification-gate.ps1"
        log = $logName
        stdout_sha256 = Get-Sha256Text -Text ""
        stderr_sha256 = Get-Sha256Text -Text $fatalError.Exception.Message
        stdout_lines = 0
        stderr_lines = 1
        result_schema = ""
        result_status = ""
    }) | Out-Null
}

$requiredSteps = @($steps | Where-Object { $_.requirement -eq "required" -and $_.verification_check })
$requiredExecuted = @($requiredSteps | Where-Object { $_.execution -eq "ran" })
$requiredSatisfied = @($requiredExecuted | Where-Object { $_.status -in @("passed", "warning") })
$zeroRequiredFailure = ($requiredExecuted.Count -eq 0)
$failedSteps = @($steps | Where-Object { $_.status -eq "failed" })
$warnings = @($steps | Where-Object { $_.status -eq "warning" })
$status = if ($failedSteps.Count -gt 0 -or $zeroRequiredFailure) { "failed" } elseif ($warnings.Count -gt 0) { "warning" } else { "passed" }
$gitSnapshot = Get-GitSnapshot
$toolVersions = Get-ToolVersions
$surfaceSignals = @()
$surfaceSchema = ""
$surfaceStatus = if ($stepResults.ContainsKey("test-surface-detection")) { $stepResults["test-surface-detection"].record.status } else { "failed" }
if ($testSurface) {
    $surfaceSchema = ConvertTo-SafeText -Text ([string]$testSurface.schema)
    $surfaceSignals = @($testSurface.signals | ForEach-Object { ConvertTo-SafeText -Text ([string]$_) } | Sort-Object -Unique)
}

$record = [ordered]@{
    schema = "codex-verification-gate-v2"
    id = $runId
    attempt_id = $attemptId
    status = $status
    mode = $Mode
    created_at = $startedAt.ToString("o")
    completed_at = (Get-Date).ToString("o")
    duration_ms = [int]((Get-Date) - $startedAt).TotalMilliseconds
    project = [ordered]@{
        name = ConvertTo-SafeText -Text (Split-Path -Leaf $root)
        root_sha256 = Get-Sha256Text -Text $root.ToLowerInvariant()
    }
    parameters = [ordered]@{
        base_ref = ConvertTo-SafeText -Text $BaseRef
        continue_on_error = [bool]$ContinueOnError
        step_timeout_seconds = $StepTimeoutSeconds
        skip = [ordered]@{
            lint = [bool]$SkipLint
            build = [bool]$SkipBuild
            cargo = [bool]$SkipCargo
        }
    }
    git = $gitSnapshot
    tools = $toolVersions
    test_surface = [ordered]@{
        schema = $surfaceSchema
        status = $surfaceStatus
        signals = $surfaceSignals
        recommended_count = $surfaceCandidates.Count
        selected_count = @($selection | Where-Object { $_.disposition -in @("executed", "covered") }).Count
        selection = $selection.ToArray()
    }
    required = [ordered]@{
        configured = $requiredSteps.Count
        executed = $requiredExecuted.Count
        satisfied = $requiredSatisfied.Count
        zero_required_failure = $zeroRequiredFailure
    }
    steps = $steps.ToArray()
}
$record | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$stepLines = if ($steps.Count -gt 0) {
    ($steps | ForEach-Object { "- $($_.status): $($_.name) [$($_.requirement), $($_.duration_ms) ms]" }) -join "`r`n"
} else {
    "- No steps ran."
}
$selectionLines = if ($selection.Count -gt 0) {
    ($selection | ForEach-Object { "- $($_.disposition): $($_.kind) ($($_.reason))" }) -join "`r`n"
} else {
    "- No detected commands were selected."
}
$md = @"
# Verification Gate

- Status: $status
- Mode: $Mode
- Attempt: $attemptId
- Created: $($startedAt.ToString("yyyy-MM-dd HH:mm:ss"))
- Project: $(Split-Path -Leaf $root)
- Base ref: $(ConvertTo-SafeText -Text $BaseRef)
- HEAD: $($gitSnapshot.head)

## Steps

$stepLines

## Test Surface

$selectionLines

## Artifacts

- verification-gate.json
- summary.md
- step logs in this folder
"@
Set-Content -LiteralPath $summaryPath -Value $md -Encoding UTF8

$resultStatus = if ($status -eq "passed") { "success" } else { $status }
$result = [ordered]@{
    status = $resultStatus
    summary = "Verification gate completed."
    id = $runId
    attempt_id = $attemptId
    mode = $Mode
    manifest = $jsonPath
    summary_path = $summaryPath
    artifacts = @($jsonPath, $summaryPath)
}
$result | ConvertTo-Json -Depth 6 -Compress

if ($status -eq "failed") {
    throw "Verification gate failed. Manifest: $jsonPath"
}
