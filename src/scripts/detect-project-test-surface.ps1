param(
    [string]$ProjectRoot = ".",
    [switch]$Markdown
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$commands = New-Object System.Collections.Generic.List[object]
$signals = New-Object System.Collections.Generic.List[string]

function Add-Command {
    param(
        [Parameter(Mandatory = $true)][string]$Kind,
        [Parameter(Mandatory = $true)][string]$Command,
        [string]$Source = "",
        [int]$Priority = 50
    )

    $commands.Add([pscustomobject]@{
        kind = $Kind
        command = $Command
        source = $Source
        priority = $Priority
    }) | Out-Null
}

function Test-File {
    param([string]$RelativePath)
    return Test-Path -LiteralPath (Join-Path $root $RelativePath) -PathType Leaf
}

function Test-Dir {
    param([string]$RelativePath)
    return Test-Path -LiteralPath (Join-Path $root $RelativePath) -PathType Container
}

function Get-NodeRunner {
    if (Test-File "pnpm-lock.yaml") { return "pnpm" }
    if (Test-File "yarn.lock") { return "yarn" }
    if (Test-File "bun.lockb") { return "bun" }
    if (Test-File "package-lock.json") { return "npm" }
    return "npm"
}

function Add-PackageJsonCommands {
    $packagePath = Join-Path $root "package.json"
    if (-not (Test-Path -LiteralPath $packagePath)) { return }

    $signals.Add("package.json") | Out-Null
    $runner = Get-NodeRunner
    $package = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json
    if (-not $package.scripts) { return }

    $scriptNames = @($package.scripts.PSObject.Properties.Name)
    foreach ($name in $scriptNames) {
        $cmd = "$runner run $name"
        $value = [string]$package.scripts.$name
        $source = "package.json:scripts.$name"

        if ($name -eq "build") { Add-Command -Kind "build" -Command $cmd -Source $source -Priority 10; continue }
        if ($name -match '^(typecheck|type-check|check:types|tsc)$' -or $value -match '\btsc\b') {
            Add-Command -Kind "typecheck" -Command $cmd -Source $source -Priority 15
            continue
        }
        if ($name -eq "lint" -or $name -match '^lint:') { Add-Command -Kind "lint" -Command $cmd -Source $source -Priority 20; continue }
        if ($name -eq "test" -or $name -match '^(test:unit|unit|vitest|jest)$') {
            Add-Command -Kind "unit-test" -Command $cmd -Source $source -Priority 25
            continue
        }
        if ($name -match '(e2e|playwright)' -or $value -match 'playwright') {
            Add-Command -Kind "e2e" -Command $cmd -Source $source -Priority 35
            continue
        }
        if ($name -match 'coverage' -or $value -match 'coverage') {
            Add-Command -Kind "coverage" -Command $cmd -Source $source -Priority 40
            continue
        }
        if ($name -match 'smoke') {
            Add-Command -Kind "smoke" -Command $cmd -Source $source -Priority 30
            continue
        }
        if ($name -match '^(dev|start)$') {
            Add-Command -Kind "runtime" -Command $cmd -Source $source -Priority 80
            continue
        }
    }

    if ((Test-File "playwright.config.ts") -or (Test-File "playwright.config.js")) {
        Add-Command -Kind "e2e" -Command "npx playwright test" -Source "playwright.config" -Priority 36
    }
}

function Add-OtherProjectCommands {
    if (Test-File "pyproject.toml") {
        $signals.Add("pyproject.toml") | Out-Null
        if ((Test-Dir "tests") -or (Test-Dir "test")) {
            Add-Command -Kind "unit-test" -Command "python -m pytest" -Source "pyproject.toml + tests" -Priority 25
        }
    }
    if (Test-File "Cargo.toml") {
        $signals.Add("Cargo.toml") | Out-Null
        Add-Command -Kind "typecheck" -Command "cargo check" -Source "Cargo.toml" -Priority 15
        Add-Command -Kind "unit-test" -Command "cargo test" -Source "Cargo.toml" -Priority 25
    }
    if (Test-File "go.mod") {
        $signals.Add("go.mod") | Out-Null
        Add-Command -Kind "unit-test" -Command "go test ./..." -Source "go.mod" -Priority 25
    }
    if (@(Get-ChildItem -LiteralPath $root -Filter "*.sln" -File -ErrorAction SilentlyContinue).Count -gt 0) {
        $signals.Add("dotnet-solution") | Out-Null
        Add-Command -Kind "build" -Command "dotnet build" -Source "*.sln" -Priority 10
        Add-Command -Kind "unit-test" -Command "dotnet test" -Source "*.sln" -Priority 25
    }
    if (Test-File "deploy\verify-package.ps1") {
        $signals.Add("codex-harness-package") | Out-Null
        Add-Command -Kind "package-verify" -Command ".\deploy\verify-package.ps1" -Source "deploy\verify-package.ps1" -Priority 5
    }
    foreach ($script in @(
        @{ rel = "scripts\verify-harness.ps1"; kind = "harness-verify"; priority = 5 },
        @{ rel = "scripts\check-all.ps1"; kind = "full-gate"; priority = 45 },
        @{ rel = "scripts\check-features.ps1"; kind = "feature-list"; priority = 20 },
        @{ rel = "scripts\invoke-verification-gate.ps1"; kind = "verification-gate"; priority = 30 }
    )) {
        if (Test-File $script.rel) {
            Add-Command -Kind $script.kind -Command ".\$($script.rel)" -Source $script.rel -Priority $script.priority
        }
    }
}

Add-PackageJsonCommands
Add-OtherProjectCommands

$orderedCommands = @($commands | Sort-Object priority, kind, command)
$recommendedQuick = @($orderedCommands | Where-Object { $_.kind -in @("package-verify", "harness-verify", "build", "typecheck", "lint", "unit-test") } | Select-Object -First 4)
$recommendedRuntime = @($orderedCommands | Where-Object { $_.kind -in @("smoke", "e2e", "runtime", "verification-gate", "full-gate") } | Select-Object -First 4)

$result = [ordered]@{
    schema = "codex-project-test-surface-v1"
    status = "success"
    project_root = $root
    signals = @($signals | Sort-Object -Unique)
    commands = $orderedCommands
    recommended = [ordered]@{
        quick = $recommendedQuick
        runtime = $recommendedRuntime
    }
}

if ($Markdown) {
    "# Project Test Surface"
    ""
    "- Project: $root"
    "- Signals: $((@($signals | Sort-Object -Unique)) -join ', ')"
    ""
    "## Commands"
    foreach ($cmd in $orderedCommands) {
        "- $($cmd.kind): `$($cmd.command)` ($($cmd.source))"
    }
} else {
    $result | ConvertTo-Json -Depth 8 -Compress
}
