param(
    [string]$CodexHome = "$env:USERPROFILE\.codex"
)

$ErrorActionPreference = "Stop"
$codexHomePath = (Resolve-Path -LiteralPath $CodexHome).Path
$gate = Join-Path $codexHomePath "scripts\invoke-verification-gate.ps1"
if (-not (Test-Path -LiteralPath $gate -PathType Leaf)) {
    throw "Verification gate script missing: $gate"
}

function Write-FixtureScript {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Body
    )

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Set-Content -LiteralPath $Path -Value $Body -Encoding UTF8
}

function New-FixtureProject {
    param(
        [Parameter(Mandatory = $true)][string]$Parent,
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$FeatureBody = "[ordered]@{ status = 'success'; summary = 'features passed' } | ConvertTo-Json -Compress",
        [string]$ArchitectureBody = "[ordered]@{ status = 'success'; summary = 'architecture passed' } | ConvertTo-Json -Compress",
        [string]$SurfaceJson = ""
    )

    $root = Join-Path $Parent $Name
    New-Item -ItemType Directory -Force -Path (Join-Path $root "scripts") | Out-Null
    Set-Content -LiteralPath (Join-Path $root "mission.md") -Value "fixture" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $root "CONTEXT.md") -Value "fixture" -Encoding UTF8

    if (-not $SurfaceJson) {
        $SurfaceJson = [ordered]@{
            schema = "codex-project-test-surface-v1"
            status = "success"
            project_root = $root
            signals = @("fixture")
            commands = @()
            recommended = [ordered]@{ quick = @(); runtime = @() }
        } | ConvertTo-Json -Depth 8 -Compress
    }
    $escapedSurface = $SurfaceJson.Replace("'", "''")
    Write-FixtureScript -Path (Join-Path $root "scripts\detect-project-test-surface.ps1") -Body "Write-Output '$escapedSurface'"
    Write-FixtureScript -Path (Join-Path $root "scripts\check-project-docs.ps1") -Body @'
param([string]$BaseRef = "HEAD~1")
[ordered]@{ status = "success"; summary = "docs passed"; base_ref = $BaseRef } | ConvertTo-Json -Compress
'@
    Write-FixtureScript -Path (Join-Path $root "scripts\check-features.ps1") -Body $FeatureBody
    if ($null -ne $ArchitectureBody) {
        Write-FixtureScript -Path (Join-Path $root "scripts\check-architecture.ps1") -Body $ArchitectureBody
    }
    return $root
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

function Get-LatestGateManifest {
    param([Parameter(Mandatory = $true)][string]$Root)

    $manifest = Get-ChildItem -LiteralPath (Join-Path $Root "artifacts\verification-gates") -Recurse -Filter "verification-gate.json" -File |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if (-not $manifest) { throw "Verification gate manifest was not created under $Root." }
    return (Get-Content -LiteralPath $manifest.FullName -Raw | ConvertFrom-Json)
}

$tmpParent = Join-Path $env:TEMP ("codex-verification-gate-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmpParent | Out-Null
try {
    $surfaceMarker = "surface-command-private-marker"
    $passRoot = New-FixtureProject -Parent $tmpParent -Name "pass"
    git -C $passRoot init | Out-Null
    git -C $passRoot config user.email "codex@example.local" | Out-Null
    git -C $passRoot config user.name "Codex Eval" | Out-Null
    git -C $passRoot add -- . | Out-Null
    git -C $passRoot commit -m "fixture" | Out-Null
    Set-Content -LiteralPath (Join-Path $passRoot "changed.txt") -Value "working diff" -Encoding UTF8

    $surface = [ordered]@{
        schema = "codex-project-test-surface-v1"
        status = "success"
        project_root = $passRoot
        signals = @("package.json")
        commands = @(
            [ordered]@{ kind = "unit-test"; command = "Write-Output '$surfaceMarker'"; source = "package.json:scripts.test"; priority = 25 }
        )
        recommended = [ordered]@{
            quick = @([ordered]@{ kind = "unit-test"; command = "Write-Output '$surfaceMarker'"; source = "package.json:scripts.test"; priority = 25 })
            runtime = @()
        }
    } | ConvertTo-Json -Depth 8 -Compress
    $escapedSurface = $surface.Replace("'", "''")
    Write-FixtureScript -Path (Join-Path $passRoot "scripts\detect-project-test-surface.ps1") -Body "Write-Output '$escapedSurface'"

    $passRaw = & $gate -ProjectRoot $passRoot -Mode DocsOnly -BaseRef HEAD -SkipLint -SkipBuild -SkipCargo -StepTimeoutSeconds 10
    $pass = $passRaw | ConvertFrom-Json
    $passManifestRaw = Get-Content -LiteralPath $pass.manifest -Raw
    $passManifest = $passManifestRaw | ConvertFrom-Json
    if ($passManifest.schema -ne "codex-verification-gate-v2" -or -not $passManifest.attempt_id -or
        $passManifest.status -ne "passed" -or $passManifest.parameters.base_ref -ne "HEAD" -or
        -not $passManifest.parameters.skip.lint -or -not $passManifest.parameters.skip.build -or
        -not $passManifest.parameters.skip.cargo -or -not $passManifest.git.head -or
        -not $passManifest.git.diff.sha256 -or -not $passManifest.tools.powershell -or
        $passManifest.required.executed -lt 2) {
        throw "Passing gate lacks the v2 parameters, git, tools, or required-step manifest contract."
    }
    if ($passManifest.test_surface.selection.Count -lt 1 -or
        $passManifest.test_surface.selection[0].disposition -ne "excluded" -or
        -not $passManifest.test_surface.selection[0].reason) {
        throw "DocsOnly gate did not justify the detected test-surface selection."
    }
    if ($passManifestRaw -match [regex]::Escape($passRoot) -or $passManifestRaw -match $surfaceMarker) {
        throw "Verification gate manifest contains an absolute project path or raw detected command."
    }

    $secondRaw = & $gate -ProjectRoot $passRoot -Mode DocsOnly -BaseRef HEAD -StepTimeoutSeconds 10
    $second = $secondRaw | ConvertFrom-Json
    if ($second.attempt_id -eq $pass.attempt_id -or $second.id -eq $pass.id) {
        throw "Verification gate attempt identifiers are not unique."
    }

    $missingRoot = New-FixtureProject -Parent $tmpParent -Name "missing-required"
    Move-Item -LiteralPath (Join-Path $missingRoot "scripts\check-features.ps1") -Destination (Join-Path $missingRoot "scripts\check-features.disabled")
    Assert-Fails -Message "Missing required gate script did not fail closed." -Action {
        & $gate -ProjectRoot $missingRoot -Mode DocsOnly -ContinueOnError -StepTimeoutSeconds 10
    }
    $missingManifest = Get-LatestGateManifest -Root $missingRoot
    $missingStep = @($missingManifest.steps | Where-Object { $_.name -eq "feature-list" })
    if ($missingStep.Count -ne 1 -or $missingStep[0].status -ne "failed" -or $missingStep[0].requirement -ne "required") {
        throw "Missing required step was not recorded as a required failure."
    }

    $plainRoot = New-FixtureProject -Parent $tmpParent -Name "plain-output" -FeatureBody "Write-Output 'plain text'"
    Assert-Fails -Message "Non-JSON output from a structured step did not fail closed." -Action {
        & $gate -ProjectRoot $plainRoot -Mode DocsOnly -ContinueOnError -StepTimeoutSeconds 10
    }

    $exitRoot = New-FixtureProject -Parent $tmpParent -Name "nonzero-output" -FeatureBody 'Write-Output ''{"status":"success"}''; exit 7'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $exitRoot "scripts\check-features.ps1") | Out-Null
    if ($LASTEXITCODE -ne 7) { throw "Nonzero fixture did not produce exit code 7." }
    Assert-Fails -Message "Structured success with a nonzero process exit did not fail." -Action {
        & $gate -ProjectRoot $exitRoot -Mode DocsOnly -ContinueOnError -StepTimeoutSeconds 10
    }
    $exitManifest = Get-LatestGateManifest -Root $exitRoot
    $exitStep = @($exitManifest.steps | Where-Object { $_.name -eq "feature-list" })[0]
    if ($exitStep.exit_code -ne 7 -or $exitStep.status -ne "failed") {
        throw "Gate did not combine structured status with process success."
    }

    $nativeExitBody = @'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -Command 'exit 7' | Out-Null
Write-Output '{"status":"success"}'
'@
    $nativeExitRoot = New-FixtureProject -Parent $tmpParent -Name "native-nonzero-output" -FeatureBody $nativeExitBody
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $nativeExitRoot "scripts\check-features.ps1") | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Native nonzero fixture did not finish with a success-shaped script process." }
    $handledNativeRaw = & $gate -ProjectRoot $nativeExitRoot -Mode DocsOnly -ContinueOnError -StepTimeoutSeconds 10
    $handledNative = $handledNativeRaw | ConvertFrom-Json
    if ($handledNative.status -ne "success") {
        $handledManifest = Get-Content -LiteralPath $handledNative.manifest -Raw | ConvertFrom-Json
        $handledFailures = @($handledManifest.steps | Where-Object { $_.status -eq "failed" } | ForEach-Object {
            "{0}:{1}:{2}" -f $_.name, $_.failure_code, $_.exit_code
        }) -join ","
        throw "A handled native probe leaked through the script process contract: $handledFailures"
    }

    $nativeSurfaceRoot = Join-Path $tmpParent "native-command-surface"
    $nativeSurfaceCommand = "& powershell.exe -NoProfile -ExecutionPolicy Bypass -Command 'exit 7' | Out-Null; Write-Output 'success-shaped-output'"
    $nativeSurface = [ordered]@{
        schema = "codex-project-test-surface-v1"
        status = "success"
        project_root = $nativeSurfaceRoot
        signals = @("native-command")
        commands = @([ordered]@{ kind = "unit-test"; command = $nativeSurfaceCommand; source = "fixture:native-command"; priority = 25 })
        recommended = [ordered]@{
            quick = @([ordered]@{ kind = "unit-test"; command = $nativeSurfaceCommand; source = "fixture:native-command"; priority = 25 })
            runtime = @()
        }
    } | ConvertTo-Json -Depth 8 -Compress
    $nativeSurfaceRoot = New-FixtureProject -Parent $tmpParent -Name "native-command-surface" -SurfaceJson $nativeSurface
    Assert-Fails -Message "A direct test-surface command hid its native nonzero exit code." -Action {
        & $gate -ProjectRoot $nativeSurfaceRoot -Mode Runtime -ContinueOnError -StepTimeoutSeconds 10
    }
    $nativeSurfaceManifest = Get-LatestGateManifest -Root $nativeSurfaceRoot
    $nativeSurfaceStep = @($nativeSurfaceManifest.steps | Where-Object { $_.origin -eq "test-surface" -and $_.verification_check })[0]
    if ($nativeSurfaceStep.exit_code -ne 7 -or $nativeSurfaceStep.status -ne "failed") {
        throw "Gate did not propagate a direct test-surface native exit code."
    }

    $runtimeRoot = New-FixtureProject -Parent $tmpParent -Name "surface-driven"
    Write-FixtureScript -Path (Join-Path $runtimeRoot "scripts\surface-check.ps1") -Body "Write-Output 'surface-ok'"
    $runtimeCommand = "& '.\scripts\surface-check.ps1'"
    $runtimeSurface = [ordered]@{
        schema = "codex-project-test-surface-v1"
        status = "success"
        project_root = $runtimeRoot
        signals = @("fixture-runtime")
        commands = @([ordered]@{ kind = "unit-test"; command = $runtimeCommand; source = "scripts\surface-check.ps1"; priority = 25 })
        recommended = [ordered]@{
            quick = @([ordered]@{ kind = "unit-test"; command = $runtimeCommand; source = "scripts\surface-check.ps1"; priority = 25 })
            runtime = @()
        }
    } | ConvertTo-Json -Depth 8 -Compress
    $escapedRuntimeSurface = $runtimeSurface.Replace("'", "''")
    Write-FixtureScript -Path (Join-Path $runtimeRoot "scripts\detect-project-test-surface.ps1") -Body "Write-Output '$escapedRuntimeSurface'"
    $runtimeRaw = & $gate -ProjectRoot $runtimeRoot -Mode Runtime -StepTimeoutSeconds 10
    $runtime = $runtimeRaw | ConvertFrom-Json
    $runtimeManifest = Get-Content -LiteralPath $runtime.manifest -Raw | ConvertFrom-Json
    $surfaceStep = @($runtimeManifest.steps | Where-Object { $_.origin -eq "test-surface" })
    if ($surfaceStep.Count -ne 1 -or $surfaceStep[0].status -ne "passed" -or $surfaceStep[0].output_contract -ne "unstructured") {
        throw "Detected test surface did not drive an explicitly unstructured runtime check."
    }

    $zeroRoot = New-FixtureProject -Parent $tmpParent -Name "zero-required"
    Assert-Fails -Message "Runtime gate passed without a required verification check." -Action {
        & $gate -ProjectRoot $zeroRoot -Mode Runtime -ContinueOnError -StepTimeoutSeconds 10
    }
    $zeroManifest = Get-LatestGateManifest -Root $zeroRoot
    if (-not $zeroManifest.required.zero_required_failure) {
        throw "Zero-required verification failure was not recorded."
    }

    $timeoutRoot = New-FixtureProject -Parent $tmpParent -Name "timeout-tree"
    $latePath = Join-Path $timeoutRoot "late-child.txt"
    $escapedLatePath = $latePath.Replace("'", "''")
    $childCommand = "Start-Sleep -Seconds 2; Set-Content -LiteralPath '$escapedLatePath' -Value 'late'"
    $encodedChild = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childCommand))
    $timeoutBody = "Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-EncodedCommand','$encodedChild') -WindowStyle Hidden | Out-Null; Start-Sleep -Seconds 8; Write-Output '{`"status`":`"success`"}'"
    Write-FixtureScript -Path (Join-Path $timeoutRoot "scripts\check-features.ps1") -Body $timeoutBody
    Assert-Fails -Message "Per-step timeout was not enforced." -Action {
        & $gate -ProjectRoot $timeoutRoot -Mode DocsOnly -ContinueOnError -StepTimeoutSeconds 1
    }
    Start-Sleep -Seconds 3
    if (Test-Path -LiteralPath $latePath) { throw "Gate timeout did not terminate the descendant process tree." }
    $timeoutManifest = Get-LatestGateManifest -Root $timeoutRoot
    $timeoutStep = @($timeoutManifest.steps | Where-Object { $_.name -eq "feature-list" })[0]
    if (-not $timeoutStep.timed_out -or $timeoutStep.exit_code -ne 124) {
        throw "Timed-out gate step did not record timeout exit semantics."
    }

    [ordered]@{
        status = "success"
        summary = "Verification gate v2 checks passed."
        cases = @(
            "sanitized-manifest",
            "unique-attempt",
            "required-missing",
            "structured-json",
            "process-success",
            "handled-native-probe",
            "native-exit-propagation",
            "test-surface-driven",
            "zero-required",
            "timeout-process-tree"
        )
    } | ConvertTo-Json -Depth 5 -Compress
} finally {
    if (Test-Path -LiteralPath $tmpParent) { Remove-Item -LiteralPath $tmpParent -Recurse -Force }
}
