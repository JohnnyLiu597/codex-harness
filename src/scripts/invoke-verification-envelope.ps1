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
    [int]$TimeoutSeconds = 0,
    [string]$SandboxMode = "unknown",
    [string]$ApprovalPolicy = "unknown",
    [string]$NetworkPolicy = "unknown",
    [switch]$AllowProtectedChanges
)

$ErrorActionPreference = "Stop"

function ConvertTo-Slug {
    param([string]$Value)
    $slug = ($Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ($slug) { return $slug }
    return "verification"
}

function Get-Sha256Text {
    param([string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Text)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-PathDigest {
    param([string]$Root, [string]$RelativePath)
    $path = if ([IO.Path]::IsPathRooted($RelativePath)) { $RelativePath } else { Join-Path $Root $RelativePath }
    if (-not (Test-Path -LiteralPath $path)) {
        return [ordered]@{ path = $RelativePath; type = "missing"; sha256 = ""; files = 0 }
    }
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        return [ordered]@{ path = $RelativePath; type = "file"; sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant(); files = 1 }
    }
    $prefix = (Resolve-Path -LiteralPath $path).Path.TrimEnd('\') + '\'
    $lines = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $path -Recurse -Force -File | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($prefix.Length)
        $lines += "$relative|$((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant())"
    }
    return [ordered]@{ path = $RelativePath; type = "directory"; sha256 = Get-Sha256Text -Text ($lines -join "`n"); files = $lines.Count }
}

function Get-EnvironmentSnapshot {
    param([string]$Root)
    $branch = ""
    $head = ""
    try {
        $branch = [string](git -C $Root branch --show-current 2>$null)
        $head = [string](git -C $Root rev-parse HEAD 2>$null)
    } catch { }
    $memoryMb = $null
    try { $memoryMb = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB) } catch { }
    $gitDirty = $null
    try { $gitDirty = @(git -C $Root status --porcelain=v1 2>$null).Count -gt 0 } catch { }
    return [ordered]@{
        os = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
        os_architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
        process_architecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
        powershell = $PSVersionTable.PSVersion.ToString()
        processor_count = [Environment]::ProcessorCount
        total_memory_mb = $memoryMb
        branch = $branch
        head = $head
        git_dirty = $gitDirty
        proxy_present = [bool]($env:HTTP_PROXY -or $env:HTTPS_PROXY -or $env:ALL_PROXY)
    }
}

function Get-AggregateDigest {
    param([object[]]$Digests)

    if ($Digests.Count -eq 0) { return "" }
    return Get-Sha256Text -Text ($Digests | ConvertTo-Json -Depth 12 -Compress)
}

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$id = "$stamp-$(ConvertTo-Slug -Value $Name)"
$runDir = Join-Path $root ("artifacts\verification-envelopes\" + $id)
$manifestPath = Join-Path $runDir "envelope.json"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$protectedBefore = @($ProtectedPaths | ForEach-Object { Get-PathDigest -Root $root -RelativePath $_ })
$sourceDigests = @($SourcePaths | ForEach-Object { Get-PathDigest -Root $root -RelativePath $_ })
$testDigests = @($TestPaths | ForEach-Object { Get-PathDigest -Root $root -RelativePath $_ })
$graderDigests = @($GraderPaths | ForEach-Object { Get-PathDigest -Root $root -RelativePath $_ })
$environment = Get-EnvironmentSnapshot -Root $root
$commandHash = Get-Sha256Text -Text $Command
$encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("`$ErrorActionPreference = 'Stop'; " + $Command))
$started = Get-Date
$output = @()
$exitCode = 0

Push-Location $root
try {
    if ($TimeoutSeconds -gt 0) {
        $process = Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-EncodedCommand", $encodedCommand) -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $runDir "stdout.tmp") -RedirectStandardError (Join-Path $runDir "stderr.tmp")
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill()
            $process.WaitForExit()
            $exitCode = 124
        } else {
            $process.WaitForExit()
            $process.Refresh()
            $exitCode = [int]$process.ExitCode
        }
        foreach ($tempName in @("stdout.tmp", "stderr.tmp")) {
            $tempPath = Join-Path $runDir $tempName
            if (Test-Path -LiteralPath $tempPath) { $output += @(Get-Content -LiteralPath $tempPath -ErrorAction SilentlyContinue) }
        }
    } else {
        $output = @(& powershell.exe -NoProfile -EncodedCommand $encodedCommand 2>&1)
        $exitCode = $LASTEXITCODE
    }
} finally {
    Pop-Location
}

$protectedAfter = @($ProtectedPaths | ForEach-Object { Get-PathDigest -Root $root -RelativePath $_ })
$evidence = @($EvidencePaths | ForEach-Object { Get-PathDigest -Root $root -RelativePath $_ })
$changes = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $protectedBefore.Count; $i++) {
    if ($protectedBefore[$i].sha256 -ne $protectedAfter[$i].sha256 -or $protectedBefore[$i].type -ne $protectedAfter[$i].type) {
        $changes.Add([string]$protectedBefore[$i].path) | Out-Null
    }
}

$outputText = ($output | ForEach-Object { [string]$_ }) -join "`n"
$status = if ($exitCode -eq 0 -and ($AllowProtectedChanges -or $changes.Count -eq 0)) { "passed" } else { "failed" }
$manifest = [ordered]@{
    schema = "codex-verification-envelope-v1"
    id = $id
    name = $Name
    status = $status
    created_at = (Get-Date).ToString("o")
    duration_ms = [math]::Round(((Get-Date) - $started).TotalMilliseconds)
    project_root = $root
    command = [ordered]@{
        label = $CommandLabel
        sha256 = $commandHash
        exit_code = $exitCode
        output_sha256 = Get-Sha256Text -Text $outputText
        output_lines = $output.Count
        timeout_seconds = $TimeoutSeconds
    }
    policy = [ordered]@{
        sandbox_mode = $SandboxMode
        approval_policy = $ApprovalPolicy
        network_policy = $NetworkPolicy
        allow_protected_changes = [bool]$AllowProtectedChanges
    }
    environment = $environment
    environment_sha256 = Get-Sha256Text -Text ($environment | ConvertTo-Json -Depth 8 -Compress)
    inputs = [ordered]@{
        source = $sourceDigests
        source_sha256 = Get-AggregateDigest -Digests $sourceDigests
        tests = $testDigests
        tests_sha256 = Get-AggregateDigest -Digests $testDigests
        graders = $graderDigests
        graders_sha256 = Get-AggregateDigest -Digests $graderDigests
    }
    protected_before = $protectedBefore
    protected_after = $protectedAfter
    protected_changes = $changes.ToArray()
    evidence = $evidence
    script_sha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
}
$manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
$manifestHashPath = Join-Path $runDir "envelope.sha256"
$manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath $manifestHashPath -Value $manifestHash -Encoding ASCII

foreach ($temporary in @("stdout.tmp", "stderr.tmp")) {
    $temporaryPath = Join-Path $runDir $temporary
    if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
}

if ($status -eq "failed") {
    throw "Verification envelope failed. Exit code: $exitCode. Protected changes: $($changes -join ', '). Manifest: $manifestPath"
}

[ordered]@{
    status = "success"
    summary = "Verification envelope passed."
    id = $id
    manifest = $manifestPath
    manifest_sha256 = $manifestHash
    manifest_hash_file = $manifestHashPath
    output_sha256 = $manifest.command.output_sha256
} | ConvertTo-Json -Depth 8 -Compress
