param(
    [string]$CodexHome = "C:\Users\Johnny Liu\.codex"
)

$ErrorActionPreference = "Stop"

$codexHomePath = (Resolve-Path -LiteralPath $CodexHome).Path
$checks = New-Object System.Collections.Generic.List[object]

function Add-Check {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Detail = ""
    )
    $checks.Add([pscustomobject]@{
        name = $Name
        status = $Status
        detail = $Detail
    }) | Out-Null
}

function Assert-Path {
    param([string]$RelativePath)
    $path = Join-Path $codexHomePath $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing required workflow core path: $RelativePath"
    }
    Add-Check -Name "path:$RelativePath" -Status "passed" -Detail "present"
}

foreach ($rel in @(
    "scripts\codex-hook-router.ps1",
    "scripts\detect-project-test-surface.ps1",
    "scripts\invoke-codex-workflow.ps1",
    "scripts\test-codex-workflow-core.ps1"
)) {
    Assert-Path -RelativePath $rel
}

$tmpRoot = Join-Path $env:TEMP ("codex-workflow-core-test-" + [guid]::NewGuid().ToString("N"))
$tmpLogs = Join-Path $tmpRoot "hook-logs"
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null

try {
    $packageJson = @'
{
  "scripts": {
    "build": "echo build-ok",
    "typecheck": "echo types-ok",
    "lint": "echo lint-ok",
    "test": "echo test-ok",
    "e2e": "echo e2e-ok"
  }
}
'@
    Set-Content -LiteralPath (Join-Path $tmpRoot "package.json") -Value $packageJson -Encoding UTF8

    $detect = Join-Path $codexHomePath "scripts\detect-project-test-surface.ps1"
    $surface = (& $detect -ProjectRoot $tmpRoot) | ConvertFrom-Json
    $kinds = @($surface.commands | ForEach-Object { $_.kind })
    foreach ($kind in @("build", "typecheck", "lint", "unit-test", "e2e")) {
        if ($kinds -notcontains $kind) {
            throw "detect-project-test-surface did not detect $kind"
        }
    }
    Add-Check -Name "detect-project-test-surface" -Status "passed" -Detail "detected build/type/lint/test/e2e"

    $workflow = Join-Path $codexHomePath "scripts\invoke-codex-workflow.ps1"
    $workflowOutput = (& $workflow -ProjectRoot $tmpRoot -Workflow verify -Task "self-test") | ConvertFrom-Json
    if ($workflowOutput.status -ne "success") {
        throw "invoke-codex-workflow failed"
    }
    Add-Check -Name "invoke-codex-workflow" -Status "passed" -Detail "verify workflow record created"

    $router = Join-Path $codexHomePath "scripts\codex-hook-router.ps1"
    $payload = '{"message":"safe summary","secret":"sk-test-secret-that-must-not-be-logged"}'
    & $router -Event Stop -Payload $payload -LogRoot $tmpLogs -Quiet
    $latest = Get-Content -LiteralPath (Join-Path $tmpLogs "latest-stop.txt") -Raw
    $jsonl = Get-Content -LiteralPath (Get-ChildItem -LiteralPath $tmpLogs -Filter "hook-stop-*.jsonl" | Select-Object -First 1).FullName -Raw
    if ($latest -match "sk-test-secret" -or $jsonl -match "sk-test-secret") {
        throw "hook router logged a raw secret from payload"
    }
    if ($jsonl -notmatch "payload") {
        throw "hook router did not record payload metadata"
    }
    Add-Check -Name "codex-hook-router" -Status "passed" -Detail "recorded metadata without raw secret"
} finally {
    if (Test-Path -LiteralPath $tmpRoot) {
        Remove-Item -LiteralPath $tmpRoot -Recurse -Force
    }
}

[ordered]@{
    schema = "codex-workflow-core-test-v1"
    status = "success"
    codex_home = $codexHomePath
    checks = $checks.ToArray()
} | ConvertTo-Json -Depth 8 -Compress
