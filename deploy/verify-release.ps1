param(
    [ValidateSet("Fast", "Standard", "Full")]
    [string]$Level = "Fast",
    [string]$ProjectRoot = "",
    [string]$CodexHome = "$env:USERPROFILE\.codex",
    [switch]$InstallRuntime,
    [switch]$SkipGitChecks
)

$ErrorActionPreference = "Stop"

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
} else {
    $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
}

if ($Level -eq "Full") {
    $InstallRuntime = $true
}

if ($Level -eq "Fast" -and $InstallRuntime) {
    throw "Fast release verification does not install runtime. Use -Level Standard or -Level Full."
}

$steps = New-Object System.Collections.Generic.List[object]

function Invoke-ReleaseStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Script
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $global:LASTEXITCODE = 0
        try {
            $output = & $Script 2>&1
            $exitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
        if ($exitCode -ne 0) {
            throw "Step exited with code $exitCode. $($output -join "`n")"
        }
        $sw.Stop()
        $steps.Add([pscustomobject]@{
            name = $Name
            status = "passed"
            seconds = [math]::Round($sw.Elapsed.TotalSeconds, 3)
            detail = (($output | Where-Object { $_ }) -join "`n")
        }) | Out-Null
    } catch {
        $sw.Stop()
        $steps.Add([pscustomobject]@{
            name = $Name
            status = "failed"
            seconds = [math]::Round($sw.Elapsed.TotalSeconds, 3)
            detail = $_.Exception.Message
        }) | Out-Null
        throw
    }
}

function Invoke-GitCheck {
    param([string[]]$Arguments)

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & git -C $ProjectRoot @Arguments 2>&1
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE. $($output -join "`n")"
    }
    return $output
}

if (-not $SkipGitChecks) {
    Invoke-ReleaseStep -Name "git-diff-check" -Script {
        $git = Get-Command git -ErrorAction SilentlyContinue
        if (-not $git) {
            return "git not found; skipped"
        }
        Invoke-GitCheck -Arguments @("diff", "--check") | Out-Null
        Invoke-GitCheck -Arguments @("diff", "--cached", "--check") | Out-Null
        "unstaged and staged diffs have no whitespace errors"
    }
}

Invoke-ReleaseStep -Name "package-public-readiness" -Script {
    & (Join-Path $ProjectRoot "deploy\verify-package.ps1") -ProjectRoot $ProjectRoot
}

if ($Level -in @("Standard", "Full")) {
    Invoke-ReleaseStep -Name "runtime-sync-preview" -Script {
        & (Join-Path $ProjectRoot "deploy\sync-to-runtime.ps1") -ProjectRoot $ProjectRoot -CodexHome $CodexHome -DryRun
    }
}

if ($InstallRuntime) {
    Invoke-ReleaseStep -Name "runtime-sync-install" -Script {
        & (Join-Path $ProjectRoot "deploy\sync-to-runtime.ps1") -ProjectRoot $ProjectRoot -CodexHome $CodexHome
    }

    Invoke-ReleaseStep -Name "runtime-global-verify" -Script {
        $verifyScript = Join-Path $CodexHome "scripts\verify-global-harness.ps1"
        powershell -NoProfile -ExecutionPolicy Bypass -File $verifyScript -CodexHome $CodexHome
    }
}

if ($Level -eq "Full") {
    Invoke-ReleaseStep -Name "runtime-harness-evals" -Script {
        $evalScript = Join-Path $CodexHome "harness-evals\run-harness-evals.ps1"
        powershell -NoProfile -ExecutionPolicy Bypass -File $evalScript -CodexHome $CodexHome
    }
}

$failed = @($steps | Where-Object { $_.status -eq "failed" })
$status = if ($failed.Count -gt 0) { "failed" } else { "success" }
$nextActions = @(switch ($Level) {
    "Fast" {
        @(
            "Commit and push when the diff is limited to docs, templates, skills, or low-risk scripts.",
            "Use -Level Standard before installing to runtime or when sync behavior changed.",
            "Use -Level Full for hook, agent, workflow, eval, sync, public-readiness, or release-critical changes."
        )
    }
    "Standard" {
        if ($InstallRuntime) {
            @("Runtime was installed and globally verified.", "Use -Level Full only when deterministic harness eval evidence is needed.")
        } else {
            @("Runtime sync was previewed only.", "Add -InstallRuntime when the current Codex runtime should receive this source change.")
        }
    }
    "Full" {
        @("Runtime was installed, globally verified, and deterministic harness evals ran.")
    }
})

[ordered]@{
    status = $status
    level = $Level
    installed_runtime = [bool]$InstallRuntime
    project_root = $ProjectRoot
    codex_home = $CodexHome
    steps = $steps.ToArray()
    next_actions = $nextActions
} | ConvertTo-Json -Depth 8 -Compress
