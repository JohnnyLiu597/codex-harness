param(
    [string]$CodexHome = "$env:USERPROFILE\.codex"
)

$ErrorActionPreference = "Stop"
$codexHomePath = (Resolve-Path -LiteralPath $CodexHome).Path
$script = Join-Path $codexHomePath "scripts\invoke-verification-envelope.ps1"
if (-not (Test-Path -LiteralPath $script -PathType Leaf)) {
    throw "Verification envelope script missing: $script"
}

$tmpRoot = Join-Path $env:TEMP ("codex-verification-envelope-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
try {
    Set-Content -LiteralPath (Join-Path $tmpRoot "protected.txt") -Value "baseline" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $tmpRoot "evidence.txt") -Value "evidence" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $tmpRoot "source.txt") -Value "source" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $tmpRoot "test.txt") -Value "test" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $tmpRoot "grader.txt") -Value "grader" -Encoding UTF8

    $passRaw = & $script `
        -ProjectRoot $tmpRoot `
        -Name "pass" `
        -Command "Get-Content -LiteralPath '.\protected.txt' | Out-Null" `
        -CommandLabel "read protected fixture" `
        -ProtectedPaths @("protected.txt") `
        -EvidencePaths @("evidence.txt") `
        -SourcePaths @("source.txt") `
        -TestPaths @("test.txt") `
        -GraderPaths @("grader.txt")
    $pass = $passRaw | ConvertFrom-Json
    if (-not (Test-Path -LiteralPath $pass.manifest)) { throw "Passing manifest missing." }
    $manifest = Get-Content -LiteralPath $pass.manifest -Raw | ConvertFrom-Json
    if ($manifest.status -ne "passed" -or -not $manifest.environment.os -or -not $manifest.command.sha256 -or
        -not $manifest.environment_sha256 -or -not $manifest.inputs.source_sha256 -or
        -not $manifest.inputs.tests_sha256 -or -not $manifest.inputs.graders_sha256) {
        throw "Passing envelope lacks status, environment, command, source, test, or grader hashes."
    }
    if (-not $pass.manifest_sha256 -or -not (Test-Path -LiteralPath $pass.manifest_hash_file)) {
        throw "Passing envelope lacks a detached manifest hash."
    }

    $boundedRaw = & $script `
        -ProjectRoot $tmpRoot `
        -Name "bounded success" `
        -Command "Get-Content -LiteralPath '.\source.txt' | Out-Null" `
        -SourcePaths @("source.txt") `
        -TimeoutSeconds 10
    $bounded = $boundedRaw | ConvertFrom-Json
    $boundedManifest = Get-Content -LiteralPath $bounded.manifest -Raw | ConvertFrom-Json
    if ($boundedManifest.status -ne "passed" -or $boundedManifest.command.exit_code -ne 0) {
        throw "Bounded successful verification did not preserve a zero exit code."
    }

    $tamperCaught = $false
    try {
        & $script -ProjectRoot $tmpRoot -Name "tamper" -Command "Set-Content -LiteralPath '.\protected.txt' -Value 'changed'" -CommandLabel "tamper fixture" -ProtectedPaths @("protected.txt") | Out-Null
    } catch {
        $tamperCaught = $true
    }
    if (-not $tamperCaught) { throw "Protected-path tampering was not detected." }

    $timeoutCaught = $false
    try {
        & $script -ProjectRoot $tmpRoot -Name "timeout" -Command "Start-Sleep -Seconds 2" -TimeoutSeconds 1 | Out-Null
    } catch {
        $timeoutCaught = $true
    }
    if (-not $timeoutCaught) { throw "Verification timeout was not enforced." }

    [ordered]@{
        status = "success"
        summary = "Verification envelope checks passed."
        cases = @("pass", "bounded-success", "protected-path-tamper", "timeout")
    } | ConvertTo-Json -Depth 5 -Compress
} finally {
    if (Test-Path -LiteralPath $tmpRoot) { Remove-Item -LiteralPath $tmpRoot -Recurse -Force }
}
