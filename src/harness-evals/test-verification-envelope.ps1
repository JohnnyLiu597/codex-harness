param(
    [string]$CodexHome = "$env:USERPROFILE\.codex"
)

$ErrorActionPreference = "Stop"
$codexHomePath = (Resolve-Path -LiteralPath $CodexHome).Path
$script = Join-Path $codexHomePath "scripts\invoke-verification-envelope.ps1"
if (-not (Test-Path -LiteralPath $script -PathType Leaf)) {
    throw "Verification envelope script missing: $script"
}

function Assert-Fails {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $caught = $false
    try {
        & $Action | Out-Null
    } catch {
        $caught = $true
    }
    if (-not $caught) { throw $Message }
}

function Get-LatestManifest {
    param([Parameter(Mandatory = $true)][string]$Root)

    $manifest = Get-ChildItem -LiteralPath (Join-Path $Root "artifacts\verification-envelopes") -Recurse -Filter "envelope.json" -File |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if (-not $manifest) { throw "Verification envelope manifest was not created under $Root." }
    return (Get-Content -LiteralPath $manifest.FullName -Raw | ConvertFrom-Json)
}

$tmpRoot = Join-Path $env:TEMP ("codex-verification-envelope-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
$oldSandboxMode = $env:CODEX_SANDBOX_MODE
$oldApprovalPolicy = $env:CODEX_APPROVAL_POLICY
$oldNetworkPolicy = $env:CODEX_NETWORK_POLICY
try {
    Set-Content -LiteralPath (Join-Path $tmpRoot "protected.txt") -Value "baseline" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $tmpRoot "evidence.txt") -Value "evidence" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $tmpRoot "source.txt") -Value "source" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $tmpRoot "test.txt") -Value "test" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $tmpRoot "grader.txt") -Value "grader" -Encoding UTF8

    $env:CODEX_SANDBOX_MODE = "workspace-write"
    $env:CODEX_APPROVAL_POLICY = "never"
    $env:CODEX_NETWORK_POLICY = "enabled"

    $passRaw = & $script `
        -ProjectRoot $tmpRoot `
        -Name "pass" `
        -Command "Write-Output 'private-output-marker'; Get-Content -LiteralPath '.\protected.txt' | Out-Null" `
        -CommandLabel "read protected fixture" `
        -ProtectedPaths @("protected.txt") `
        -EvidencePaths @("evidence.txt") `
        -SourcePaths @("source.txt") `
        -TestPaths @("test.txt") `
        -GraderPaths @("grader.txt") `
        -RequireProtectedPaths `
        -RequireEvidencePaths `
        -RequireSourcePaths `
        -RequireTestPaths `
        -RequireGraderPaths `
        -SandboxMode "workspace-write" `
        -ApprovalPolicy "never" `
        -NetworkPolicy "enabled"
    $pass = $passRaw | ConvertFrom-Json
    if (-not (Test-Path -LiteralPath $pass.manifest)) { throw "Passing manifest missing." }
    $manifestRaw = Get-Content -LiteralPath $pass.manifest -Raw
    $manifest = $manifestRaw | ConvertFrom-Json
    if ($manifest.schema -ne "codex-verification-envelope-v2" -or $manifest.status -ne "passed" -or
        -not $manifest.attempt_id -or -not $manifest.environment.os -or -not $manifest.command.sha256 -or
        -not $manifest.environment_sha256 -or -not $manifest.inputs.before.source_sha256 -or
        -not $manifest.inputs.after.source_sha256 -or -not $manifest.inputs.before.tests_sha256 -or
        -not $manifest.inputs.after.graders_sha256 -or $manifest.inputs.stale) {
        throw "Passing envelope lacks the v2 attempt, environment, before/after input, or stale-state contract."
    }
    if ($manifest.command.timeout_seconds -le 0 -or -not $manifest.command.timeout_defaulted) {
        throw "Verification envelope did not enforce a bounded default timeout."
    }
    if ($manifest.policy.declared.sandbox_mode -ne "workspace-write" -or
        $manifest.policy.observed.sandbox_mode -ne "workspace-write" -or
        -not $manifest.policy.consistent) {
        throw "Verification envelope did not preserve declared versus observed policy."
    }
    if ($manifestRaw -match [regex]::Escape($tmpRoot) -or $manifestRaw -match "private-output-marker") {
        throw "Verification envelope manifest contains an absolute project path or raw command output."
    }
    if (-not $pass.manifest_sha256 -or -not (Test-Path -LiteralPath $pass.manifest_hash_file)) {
        throw "Passing envelope lacks a detached manifest hash."
    }
    $tempRunDir = Join-Path $env:TEMP ("codex-verification-envelope-" + $pass.attempt_id)
    if (Test-Path -LiteralPath $tempRunDir) { throw "Passing envelope left its temporary run directory behind." }

    $secondRaw = & $script -ProjectRoot $tmpRoot -Name "pass" -Command "Get-Content -LiteralPath '.\source.txt' | Out-Null" -SourcePaths @("source.txt")
    $second = $secondRaw | ConvertFrom-Json
    if ($second.attempt_id -eq $pass.attempt_id -or $second.id -eq $pass.id) {
        throw "Verification envelope attempt identifiers are not unique."
    }

    Assert-Fails -Message "Missing declared evidence did not fail." -Action {
        & $script -ProjectRoot $tmpRoot -Name "missing evidence" -Command "Write-Output 'done'" -EvidencePaths @("missing-evidence.txt")
    }
    $missingEvidenceManifest = Get-LatestManifest -Root $tmpRoot
    if ("missing-evidence.txt" -notin @($missingEvidenceManifest.evidence.missing)) {
        throw "Missing evidence was not recorded in the envelope manifest."
    }

    Assert-Fails -Message "An empty required source-path set did not fail." -Action {
        & $script -ProjectRoot $tmpRoot -Name "required source" -Command "Write-Output 'done'" -RequireSourcePaths
    }

    Assert-Fails -Message "A missing required test path did not fail." -Action {
        & $script -ProjectRoot $tmpRoot -Name "required test" -Command "Write-Output 'done'" -TestPaths @("missing-test.txt") -RequireTestPaths
    }

    Set-Content -LiteralPath (Join-Path $tmpRoot "stale-source.txt") -Value "before" -Encoding UTF8
    Assert-Fails -Message "Input mutation during verification was not detected as stale." -Action {
        & $script -ProjectRoot $tmpRoot -Name "stale input" -Command "Set-Content -LiteralPath '.\stale-source.txt' -Value 'after'" -SourcePaths @("stale-source.txt") -RequireSourcePaths
    }
    $staleManifest = Get-LatestManifest -Root $tmpRoot
    if (-not $staleManifest.inputs.stale -or "stale-source.txt" -notin @($staleManifest.inputs.stale_paths)) {
        throw "Stale input paths were not recorded."
    }

    Assert-Fails -Message "Protected-path tampering was not detected." -Action {
        & $script -ProjectRoot $tmpRoot -Name "tamper" -Command "Set-Content -LiteralPath '.\protected.txt' -Value 'changed'" -CommandLabel "tamper fixture" -ProtectedPaths @("protected.txt")
    }

    Assert-Fails -Message "Observed policy mismatch did not fail closed." -Action {
        & $script -ProjectRoot $tmpRoot -Name "policy mismatch" -Command "Write-Output 'done'" -SandboxMode "read-only"
    }
    $policyManifest = Get-LatestManifest -Root $tmpRoot
    if ($policyManifest.policy.consistent -ne $false -or $policyManifest.policy.mismatches.Count -lt 1) {
        throw "Policy mismatch was not recorded."
    }

    $lateEvidence = Join-Path $tmpRoot "late-evidence.txt"
    $escapedLateEvidence = $lateEvidence.Replace("'", "''")
    $childCommand = "Start-Sleep -Seconds 2; Set-Content -LiteralPath '$escapedLateEvidence' -Value 'late'"
    $encodedChild = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childCommand))
    $timeoutCommand = "Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-EncodedCommand','$encodedChild') -WindowStyle Hidden | Out-Null; Start-Sleep -Seconds 8"
    Assert-Fails -Message "Verification timeout was not enforced." -Action {
        & $script -ProjectRoot $tmpRoot -Name "timeout tree" -Command $timeoutCommand -TimeoutSeconds 1
    }
    $timeoutManifest = Get-LatestManifest -Root $tmpRoot
    Start-Sleep -Seconds 3
    if (Test-Path -LiteralPath $lateEvidence) { throw "Timeout did not terminate the descendant process tree." }
    $timeoutTempDir = Join-Path $env:TEMP ("codex-verification-envelope-" + $timeoutManifest.attempt_id)
    if (Test-Path -LiteralPath $timeoutTempDir) { throw "Failed envelope left its temporary run directory behind." }

    [ordered]@{
        status = "success"
        summary = "Verification envelope v2 checks passed."
        cases = @(
            "pass-default-timeout",
            "unique-attempt",
            "required-paths",
            "missing-evidence",
            "stale-input",
            "protected-path-tamper",
            "declared-observed-policy",
            "timeout-process-tree",
            "temp-cleanup"
        )
    } | ConvertTo-Json -Depth 5 -Compress
} finally {
    $env:CODEX_SANDBOX_MODE = $oldSandboxMode
    $env:CODEX_APPROVAL_POLICY = $oldApprovalPolicy
    $env:CODEX_NETWORK_POLICY = $oldNetworkPolicy
    if (Test-Path -LiteralPath $tmpRoot) { Remove-Item -LiteralPath $tmpRoot -Recurse -Force }
}
