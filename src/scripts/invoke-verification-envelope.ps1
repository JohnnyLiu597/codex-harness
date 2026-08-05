param(
    [string]$ProjectRoot = ".",
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Command,
    [string]$CommandLabel = "verification",
    [string[]]$ProtectedPaths = @(),
    [string[]]$EvidencePaths = @(),
    [string[]]$SourcePaths = @(),
    [string[]]$TestPaths = @(),
    [string[]]$GraderPaths = @(),
    [ValidateRange(0, 86400)][int]$TimeoutSeconds = 0,
    [string]$SandboxMode = "unknown",
    [string]$ApprovalPolicy = "unknown",
    [string]$NetworkPolicy = "unknown",
    [switch]$AllowProtectedChanges,
    [switch]$RequireProtectedPaths,
    [switch]$RequireEvidencePaths,
    [switch]$RequireSourcePaths,
    [switch]$RequireTestPaths,
    [switch]$RequireGraderPaths
)

$ErrorActionPreference = "Stop"
$defaultTimeoutSeconds = 300
$timeoutDefaulted = ($TimeoutSeconds -le 0)
$effectiveTimeoutSeconds = if ($timeoutDefaulted) { $defaultTimeoutSeconds } else { $TimeoutSeconds }

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
    if ($script:root) {
        $value = $value.Replace($script:root, "<project>")
        $value = $value.Replace(($script:root -replace '\\', '/'), "<project>")
    }
    $value = ($value -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '').Trim()
    if ($value.Length -gt $MaxLength) { return $value.Substring(0, $MaxLength) }
    return $value
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

function Get-LineCount {
    param([AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return 0 }
    $trimmed = $Text.TrimEnd("`r", "`n")
    if ([string]::IsNullOrEmpty($trimmed)) { return 0 }
    return @($trimmed -split "`r?`n").Count
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

function Remove-OwnedTempDirectory {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return }
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $ownedPrefix = Join-Path $tempRoot "codex-verification-envelope-"
    if (-not $fullPath.StartsWith($ownedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove an unowned verification temp directory."
    }
    Remove-Item -LiteralPath $fullPath -Recurse -Force -ErrorAction SilentlyContinue
}

function Add-FailureCode {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Code
    )

    if ($Code -and -not $List.Contains($Code)) { $List.Add($Code) | Out-Null }
}

function Resolve-PathDescriptor {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$InputPath
    )

    $candidate = if ([IO.Path]::IsPathRooted($InputPath)) {
        [IO.Path]::GetFullPath($InputPath)
    } else {
        [IO.Path]::GetFullPath((Join-Path $Root $InputPath))
    }
    $normalizedRoot = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $rootPrefix = $normalizedRoot + [IO.Path]::DirectorySeparatorChar
    $insideRoot = $candidate.Equals($normalizedRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $candidate.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)
    $displayPath = if ($insideRoot) {
        if ($candidate.Equals($normalizedRoot, [StringComparison]::OrdinalIgnoreCase)) {
            "."
        } else {
            $candidate.Substring($rootPrefix.Length).Replace('\', '/')
        }
    } else {
        "<external>/" + (Get-Sha256Text -Text $candidate.ToLowerInvariant()).Substring(0, 16)
    }

    return [pscustomobject]@{
        full_path = $candidate
        path = $displayPath
    }
}

function Resolve-PathDescriptors {
    param(
        [string[]]$Paths,
        [string]$Category
    )

    $items = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($value in @($Paths)) {
        if ([string]::IsNullOrWhiteSpace([string]$value)) {
            Add-FailureCode -List $script:preflightFailures -Code ("$Category-path-empty")
            continue
        }
        try {
            $descriptor = Resolve-PathDescriptor -Root $script:root -InputPath ([string]$value)
            $key = $descriptor.full_path.ToLowerInvariant()
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $items.Add($descriptor) | Out-Null
            }
        } catch {
            Add-FailureCode -List $script:preflightFailures -Code ("$Category-path-invalid")
        }
    }
    return $items.ToArray()
}

function Get-PathDigest {
    param([object]$Descriptor)

    try {
        if (-not (Test-Path -LiteralPath $Descriptor.full_path)) {
            return [ordered]@{ path = $Descriptor.path; type = "missing"; sha256 = ""; files = 0; bytes = 0 }
        }
        if (Test-Path -LiteralPath $Descriptor.full_path -PathType Leaf) {
            $item = Get-Item -LiteralPath $Descriptor.full_path -Force -ErrorAction Stop
            return [ordered]@{
                path = $Descriptor.path
                type = "file"
                sha256 = (Get-FileHash -LiteralPath $Descriptor.full_path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
                files = 1
                bytes = [long]$item.Length
            }
        }
        if (Test-Path -LiteralPath $Descriptor.full_path -PathType Container) {
            $directoryRoot = $Descriptor.full_path.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
            $lines = New-Object System.Collections.Generic.List[string]
            $totalBytes = [long]0
            foreach ($file in @(Get-ChildItem -LiteralPath $Descriptor.full_path -Recurse -Force -File -ErrorAction Stop | Sort-Object FullName)) {
                $relative = $file.FullName.Substring($directoryRoot.Length).Replace('\', '/')
                $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
                $lines.Add("$relative|$hash") | Out-Null
                $totalBytes += [long]$file.Length
            }
            return [ordered]@{
                path = $Descriptor.path
                type = "directory"
                sha256 = Get-Sha256Text -Text ($lines -join "`n")
                files = $lines.Count
                bytes = $totalBytes
            }
        }
        return [ordered]@{ path = $Descriptor.path; type = "unsupported"; sha256 = ""; files = 0; bytes = 0 }
    } catch {
        return [ordered]@{ path = $Descriptor.path; type = "error"; sha256 = ""; files = 0; bytes = 0 }
    }
}

function Get-PathDigests {
    param([object[]]$Descriptors)

    return @($Descriptors | ForEach-Object { Get-PathDigest -Descriptor $_ })
}

function Get-AggregateDigest {
    param([object[]]$Digests)

    $json = ConvertTo-Json -InputObject @($Digests) -Depth 12 -Compress
    return Get-Sha256Text -Text $json
}

function Get-MissingPaths {
    param([object[]]$Digests)

    return @($Digests | Where-Object { $_.type -notin @("file", "directory") } | ForEach-Object { [string]$_.path })
}

function Compare-DigestSets {
    param(
        [object[]]$Before,
        [object[]]$After
    )

    $changed = New-Object System.Collections.Generic.List[string]
    $afterByPath = @{}
    foreach ($digest in @($After)) { $afterByPath[[string]$digest.path] = $digest }
    foreach ($beforeDigest in @($Before)) {
        $path = [string]$beforeDigest.path
        if (-not $afterByPath.ContainsKey($path)) {
            $changed.Add($path) | Out-Null
            continue
        }
        $afterDigest = $afterByPath[$path]
        if ($beforeDigest.type -ne $afterDigest.type -or
            $beforeDigest.sha256 -ne $afterDigest.sha256 -or
            [long]$beforeDigest.files -ne [long]$afterDigest.files -or
            [long]$beforeDigest.bytes -ne [long]$afterDigest.bytes) {
            $changed.Add($path) | Out-Null
        }
    }
    foreach ($afterDigest in @($After)) {
        if ([string]$afterDigest.path -notin @($Before | ForEach-Object { [string]$_.path })) {
            $changed.Add([string]$afterDigest.path) | Out-Null
        }
    }
    return @($changed.ToArray() | Sort-Object -Unique)
}

function Invoke-GitText {
    param([string[]]$Arguments)

    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) { return $null }
    try {
        $global:LASTEXITCODE = 0
        $output = @(& $git.Source -C $script:root @Arguments 2>$null)
        if ($LASTEXITCODE -ne 0) { return $null }
        return (($output | ForEach-Object { [string]$_ }) -join "`n").TrimEnd()
    } catch {
        return $null
    }
}

function Get-EnvironmentSnapshot {
    $branch = Invoke-GitText -Arguments @("branch", "--show-current")
    $head = Invoke-GitText -Arguments @("rev-parse", "HEAD")
    $statusText = Invoke-GitText -Arguments @("status", "--porcelain=v1")
    $memoryMb = $null
    try { $memoryMb = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB) } catch { }

    return [ordered]@{
        os = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
        os_architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
        process_architecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
        powershell = $PSVersionTable.PSVersion.ToString()
        processor_count = [Environment]::ProcessorCount
        total_memory_mb = $memoryMb
        git_available = [bool](Get-Command git -ErrorAction SilentlyContinue)
        branch = ConvertTo-SafeText -Text ([string]$branch)
        head = [string]$head
        git_dirty = if ($null -eq $statusText) { $null } else { [bool]$statusText }
        proxy_present = [bool]($env:HTTP_PROXY -or $env:HTTPS_PROXY -or $env:ALL_PROXY)
    }
}

function Normalize-PolicyValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return "unknown" }
    return $Value.Trim().ToLowerInvariant()
}

function Get-ObservedPolicy {
    return [ordered]@{
        sandbox_mode = Normalize-PolicyValue -Value $env:CODEX_SANDBOX_MODE
        approval_policy = Normalize-PolicyValue -Value $env:CODEX_APPROVAL_POLICY
        network_policy = Normalize-PolicyValue -Value $env:CODEX_NETWORK_POLICY
        source = "environment"
    }
}

function Compare-Policy {
    param(
        [object]$Declared,
        [object]$Observed
    )

    $mismatches = New-Object System.Collections.Generic.List[object]
    foreach ($field in @("sandbox_mode", "approval_policy", "network_policy")) {
        $declaredValue = [string]$Declared[$field]
        $observedValue = [string]$Observed[$field]
        if ($declaredValue -ne "unknown" -and $declaredValue -ne $observedValue) {
            $mismatches.Add([pscustomobject]@{
                field = $field
                declared = $declaredValue
                observed = $observedValue
            }) | Out-Null
        }
    }
    return [pscustomobject]@{
        consistent = ($mismatches.Count -eq 0)
        mismatches = $mismatches.ToArray()
    }
}

function Get-TaskText {
    param([object]$Task)

    if ($null -eq $Task) { return "" }
    try {
        if ($Task.Wait(5000)) { return [string]$Task.Result }
    } catch { }
    return ""
}

function Invoke-BoundedPowerShell {
    param(
        [Parameter(Mandatory = $true)][string]$CommandText,
        [Parameter(Mandatory = $true)][int]$Timeout,
        [Parameter(Mandatory = $true)][string]$TempDirectory
    )

    $runnerPath = Join-Path $TempDirectory "runner.ps1"
    $process = $null
    $stdoutTask = $null
    $stderrTask = $null
    $stdout = ""
    $stderr = ""
    $exitCode = -1
    $timedOut = $false
    $launchFailed = $false
    $started = Get-Date

    $runner = @"
`$ErrorActionPreference = 'Stop'
try {
    `$global:LASTEXITCODE = 0
$CommandText
    `$invocationSucceeded = `$?
    `$nativeExitCode = `$LASTEXITCODE
    if (-not `$invocationSucceeded) { exit 1 }
    if (`$null -ne `$nativeExitCode -and [int]`$nativeExitCode -ne 0) { exit [int]`$nativeExitCode }
    exit 0
} catch {
    [Console]::Error.WriteLine(`$_.Exception.Message)
    exit 1
}
"@

    try {
        New-Item -ItemType Directory -Force -Path $TempDirectory | Out-Null
        Set-Content -LiteralPath $runnerPath -Value $runner -Encoding UTF8

        try {
            $startInfo = New-Object System.Diagnostics.ProcessStartInfo
            $startInfo.FileName = "powershell.exe"
            $startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File " + (ConvertTo-NativeArgument -Value $runnerPath)
            $startInfo.WorkingDirectory = $script:root
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
            if (-not $process.WaitForExit($Timeout * 1000)) {
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
        $stdout = Get-TaskText -Task $stdoutTask
        $capturedError = Get-TaskText -Task $stderrTask
        if ($capturedError) { $stderr = (($stderr, $capturedError) -ne "") -join "`n" }
        if ($process) { try { $process.Dispose() } catch { } }
    }

    return [pscustomobject]@{
        stdout = $stdout
        stderr = $stderr
        exit_code = $exitCode
        timed_out = $timedOut
        launch_failed = $launchFailed
        duration_ms = [int]((Get-Date) - $started).TotalMilliseconds
    }
}

$script:root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$attemptId = [guid]::NewGuid().ToString("N")
$startedAt = Get-Date
$stamp = $startedAt.ToString("yyyyMMdd-HHmmssfff")
$id = "$stamp-$(ConvertTo-Slug -Value $Name)-$($attemptId.Substring(0, 12))"
$runDir = Join-Path $script:root ("artifacts\verification-envelopes\" + $id)
$manifestPath = Join-Path $runDir "envelope.json"
$manifestHashPath = Join-Path $runDir "envelope.sha256"
$tempRunDir = Join-Path ([IO.Path]::GetTempPath()) ("codex-verification-envelope-" + $attemptId)
$script:preflightFailures = New-Object System.Collections.Generic.List[string]
$failureCodes = New-Object System.Collections.Generic.List[string]
$pendingFailure = $null
$result = $null

New-Item -ItemType Directory -Force -Path $runDir | Out-Null

try {
    $protectedDescriptors = @(Resolve-PathDescriptors -Paths $ProtectedPaths -Category "protected")
    $evidenceDescriptors = @(Resolve-PathDescriptors -Paths $EvidencePaths -Category "evidence")
    $sourceDescriptors = @(Resolve-PathDescriptors -Paths $SourcePaths -Category "source")
    $testDescriptors = @(Resolve-PathDescriptors -Paths $TestPaths -Category "test")
    $graderDescriptors = @(Resolve-PathDescriptors -Paths $GraderPaths -Category "grader")

    $requirementMap = [ordered]@{
        protected_paths = [bool]$RequireProtectedPaths
        evidence_paths = [bool]$RequireEvidencePaths
        source_paths = [bool]$RequireSourcePaths
        test_paths = [bool]$RequireTestPaths
        grader_paths = [bool]$RequireGraderPaths
    }
    $missingRequiredSets = New-Object System.Collections.Generic.List[string]
    foreach ($requirement in @(
        [pscustomobject]@{ name = "protected_paths"; required = [bool]$RequireProtectedPaths; count = $protectedDescriptors.Count },
        [pscustomobject]@{ name = "evidence_paths"; required = [bool]$RequireEvidencePaths; count = $evidenceDescriptors.Count },
        [pscustomobject]@{ name = "source_paths"; required = [bool]$RequireSourcePaths; count = $sourceDescriptors.Count },
        [pscustomobject]@{ name = "test_paths"; required = [bool]$RequireTestPaths; count = $testDescriptors.Count },
        [pscustomobject]@{ name = "grader_paths"; required = [bool]$RequireGraderPaths; count = $graderDescriptors.Count }
    )) {
        if ($requirement.required -and $requirement.count -eq 0) {
            $missingRequiredSets.Add($requirement.name) | Out-Null
            Add-FailureCode -List $script:preflightFailures -Code ("required-" + $requirement.name.Replace('_', '-') + "-empty")
        }
    }

    $protectedBefore = @(Get-PathDigests -Descriptors $protectedDescriptors)
    $sourceBefore = @(Get-PathDigests -Descriptors $sourceDescriptors)
    $testsBefore = @(Get-PathDigests -Descriptors $testDescriptors)
    $gradersBefore = @(Get-PathDigests -Descriptors $graderDescriptors)

    $protectedMissingBefore = @(Get-MissingPaths -Digests $protectedBefore)
    $sourceMissingBefore = @(Get-MissingPaths -Digests $sourceBefore)
    $testsMissingBefore = @(Get-MissingPaths -Digests $testsBefore)
    $gradersMissingBefore = @(Get-MissingPaths -Digests $gradersBefore)
    if ($protectedMissingBefore.Count -gt 0) { Add-FailureCode -List $script:preflightFailures -Code "protected-path-missing" }
    if ($sourceMissingBefore.Count -gt 0) { Add-FailureCode -List $script:preflightFailures -Code "source-path-missing" }
    if ($testsMissingBefore.Count -gt 0) { Add-FailureCode -List $script:preflightFailures -Code "test-path-missing" }
    if ($gradersMissingBefore.Count -gt 0) { Add-FailureCode -List $script:preflightFailures -Code "grader-path-missing" }

    $declaredPolicy = [ordered]@{
        sandbox_mode = Normalize-PolicyValue -Value $SandboxMode
        approval_policy = Normalize-PolicyValue -Value $ApprovalPolicy
        network_policy = Normalize-PolicyValue -Value $NetworkPolicy
    }
    $observedPolicy = Get-ObservedPolicy
    $policyComparison = Compare-Policy -Declared $declaredPolicy -Observed $observedPolicy
    if (-not $policyComparison.consistent) { Add-FailureCode -List $script:preflightFailures -Code "policy-mismatch" }

    foreach ($failure in $script:preflightFailures) { Add-FailureCode -List $failureCodes -Code $failure }

    $environment = Get-EnvironmentSnapshot
    $commandHash = Get-Sha256Text -Text $Command
    $capture = [pscustomobject]@{
        stdout = ""
        stderr = ""
        exit_code = $null
        timed_out = $false
        launch_failed = $false
        duration_ms = 0
    }
    $executionState = "skipped-preflight"
    if ($script:preflightFailures.Count -eq 0) {
        $executionState = "ran"
        $capture = Invoke-BoundedPowerShell -CommandText $Command -Timeout $effectiveTimeoutSeconds -TempDirectory $tempRunDir
        if ($capture.timed_out) {
            Add-FailureCode -List $failureCodes -Code "process-timeout"
        } elseif ($capture.launch_failed) {
            Add-FailureCode -List $failureCodes -Code "process-launch"
        } elseif ($capture.exit_code -ne 0) {
            Add-FailureCode -List $failureCodes -Code "process-exit"
        }
    }

    $protectedAfter = @(Get-PathDigests -Descriptors $protectedDescriptors)
    $sourceAfter = @(Get-PathDigests -Descriptors $sourceDescriptors)
    $testsAfter = @(Get-PathDigests -Descriptors $testDescriptors)
    $gradersAfter = @(Get-PathDigests -Descriptors $graderDescriptors)
    $evidenceAfter = @(Get-PathDigests -Descriptors $evidenceDescriptors)

    $protectedMissingAfter = @(Get-MissingPaths -Digests $protectedAfter)
    $sourceMissingAfter = @(Get-MissingPaths -Digests $sourceAfter)
    $testsMissingAfter = @(Get-MissingPaths -Digests $testsAfter)
    $gradersMissingAfter = @(Get-MissingPaths -Digests $gradersAfter)

    $protectedChanges = @(Compare-DigestSets -Before $protectedBefore -After $protectedAfter)
    if ($protectedChanges.Count -gt 0 -and -not $AllowProtectedChanges) {
        Add-FailureCode -List $failureCodes -Code "protected-path-changed"
    }

    $stalePaths = @(
        @(Compare-DigestSets -Before $sourceBefore -After $sourceAfter) +
        @(Compare-DigestSets -Before $testsBefore -After $testsAfter) +
        @(Compare-DigestSets -Before $gradersBefore -After $gradersAfter) |
        Sort-Object -Unique
    )
    $inputsStale = ($stalePaths.Count -gt 0)
    if ($inputsStale) { Add-FailureCode -List $failureCodes -Code "input-stale" }

    $evidenceMissing = @(Get-MissingPaths -Digests $evidenceAfter)
    if ($evidenceMissing.Count -gt 0) { Add-FailureCode -List $failureCodes -Code "evidence-missing" }

    $pathResolutionFailureCount = @($script:preflightFailures | Where-Object { $_ -like "*-path-empty" -or $_ -like "*-path-invalid" }).Count
    $requirementsSatisfied = (
        $missingRequiredSets.Count -eq 0 -and
        $pathResolutionFailureCount -eq 0 -and
        $protectedMissingBefore.Count -eq 0 -and
        $protectedMissingAfter.Count -eq 0 -and
        $sourceMissingBefore.Count -eq 0 -and
        $sourceMissingAfter.Count -eq 0 -and
        $testsMissingBefore.Count -eq 0 -and
        $testsMissingAfter.Count -eq 0 -and
        $gradersMissingBefore.Count -eq 0 -and
        $gradersMissingAfter.Count -eq 0 -and
        $evidenceMissing.Count -eq 0
    )

    $status = if ($failureCodes.Count -eq 0) { "passed" } else { "failed" }
    $outputParts = New-Object System.Collections.Generic.List[string]
    if ($capture.stdout) { $outputParts.Add([string]$capture.stdout) | Out-Null }
    if ($capture.stderr) { $outputParts.Add([string]$capture.stderr) | Out-Null }
    $outputText = $outputParts -join "`n"

    $manifest = [ordered]@{
        schema = "codex-verification-envelope-v2"
        id = $id
        attempt_id = $attemptId
        name = ConvertTo-SafeText -Text $Name
        status = $status
        created_at = $startedAt.ToString("o")
        completed_at = (Get-Date).ToString("o")
        duration_ms = [int]((Get-Date) - $startedAt).TotalMilliseconds
        project = [ordered]@{
            name = ConvertTo-SafeText -Text (Split-Path -Leaf $script:root)
            root_sha256 = Get-Sha256Text -Text $script:root.ToLowerInvariant()
        }
        command = [ordered]@{
            label = ConvertTo-SafeText -Text $CommandLabel
            sha256 = $commandHash
            execution = $executionState
            exit_code = $capture.exit_code
            timed_out = [bool]$capture.timed_out
            launch_failed = [bool]$capture.launch_failed
            duration_ms = [int]$capture.duration_ms
            timeout_seconds = $effectiveTimeoutSeconds
            timeout_defaulted = $timeoutDefaulted
            output_sha256 = Get-Sha256Text -Text $outputText
            output_lines = (Get-LineCount -Text $capture.stdout) + (Get-LineCount -Text $capture.stderr)
            stdout_sha256 = Get-Sha256Text -Text $capture.stdout
            stdout_lines = Get-LineCount -Text $capture.stdout
            stderr_sha256 = Get-Sha256Text -Text $capture.stderr
            stderr_lines = Get-LineCount -Text $capture.stderr
        }
        policy = [ordered]@{
            declared = $declaredPolicy
            observed = $observedPolicy
            consistent = [bool]$policyComparison.consistent
            mismatches = @($policyComparison.mismatches)
            allow_protected_changes = [bool]$AllowProtectedChanges
        }
        environment = $environment
        environment_sha256 = Get-Sha256Text -Text ($environment | ConvertTo-Json -Depth 8 -Compress)
        requirements = [ordered]@{
            declared = $requirementMap
            missing_sets = $missingRequiredSets.ToArray()
            satisfied = $requirementsSatisfied
        }
        inputs = [ordered]@{
            before = [ordered]@{
                source = $sourceBefore
                source_sha256 = Get-AggregateDigest -Digests $sourceBefore
                tests = $testsBefore
                tests_sha256 = Get-AggregateDigest -Digests $testsBefore
                graders = $gradersBefore
                graders_sha256 = Get-AggregateDigest -Digests $gradersBefore
                missing = [ordered]@{
                    source = $sourceMissingBefore
                    tests = $testsMissingBefore
                    graders = $gradersMissingBefore
                }
            }
            after = [ordered]@{
                source = $sourceAfter
                source_sha256 = Get-AggregateDigest -Digests $sourceAfter
                tests = $testsAfter
                tests_sha256 = Get-AggregateDigest -Digests $testsAfter
                graders = $gradersAfter
                graders_sha256 = Get-AggregateDigest -Digests $gradersAfter
                missing = [ordered]@{
                    source = $sourceMissingAfter
                    tests = $testsMissingAfter
                    graders = $gradersMissingAfter
                }
            }
            stale = $inputsStale
            stale_paths = $stalePaths
        }
        protected = [ordered]@{
            required = [bool]$RequireProtectedPaths
            before = $protectedBefore
            before_sha256 = Get-AggregateDigest -Digests $protectedBefore
            after = $protectedAfter
            after_sha256 = Get-AggregateDigest -Digests $protectedAfter
            missing_before = $protectedMissingBefore
            missing_after = $protectedMissingAfter
            missing = @($protectedMissingBefore + $protectedMissingAfter | Sort-Object -Unique)
            changed = ($protectedChanges.Count -gt 0)
            changes = $protectedChanges
        }
        evidence = [ordered]@{
            required = [bool]$RequireEvidencePaths
            paths = $evidenceAfter
            sha256 = Get-AggregateDigest -Digests $evidenceAfter
            missing = $evidenceMissing
            present_count = @($evidenceAfter | Where-Object { $_.type -in @("file", "directory") }).Count
        }
        failures = $failureCodes.ToArray()
        script_sha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    $manifest | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    $manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Set-Content -LiteralPath $manifestHashPath -Value $manifestHash -Encoding ASCII

    $result = [ordered]@{
        status = "success"
        summary = "Verification envelope passed."
        id = $id
        attempt_id = $attemptId
        manifest = $manifestPath
        manifest_sha256 = $manifestHash
        manifest_hash_file = $manifestHashPath
        output_sha256 = $manifest.command.output_sha256
        artifacts = @($manifestPath, $manifestHashPath)
    }
    if ($status -eq "failed") {
        $pendingFailure = "Verification envelope failed. Manifest: $manifestPath"
    }
} finally {
    Remove-OwnedTempDirectory -Path $tempRunDir
}

if ($pendingFailure) { throw $pendingFailure }
$result | ConvertTo-Json -Depth 8 -Compress
