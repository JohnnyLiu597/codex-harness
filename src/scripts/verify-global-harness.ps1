param(
    [string]$CodexHome = "$env:USERPROFILE\.codex"
)

$ErrorActionPreference = "Stop"

$codexHomePath = (Resolve-Path -LiteralPath $CodexHome).Path
$python = Get-Command python -ErrorAction SilentlyContinue
$rg = Get-Command rg -ErrorAction SilentlyContinue
$bundledRg = "$env:LOCALAPPDATA\OpenAI\Codex\bin\rg.exe"

function Get-McpServerNames {
    param([Parameter(Mandatory = $true)][string]$Config)

    @([regex]::Matches($Config, '(?m)^\[mcp_servers\.([^\.\]]+)(?:\.[^\]]+)?\]') |
        ForEach-Object { $_.Groups[1].Value } |
        Sort-Object -Unique)
}

function Get-McpSubsections {
    param([Parameter(Mandatory = $true)][string]$Config)

    @([regex]::Matches($Config, '(?m)^\[mcp_servers\.([^\.\]]+)\.([^\]]+)\]') |
        ForEach-Object { "$($_.Groups[1].Value).$($_.Groups[2].Value)" } |
        Sort-Object -Unique)
}

function Resolve-CodexCommand {
    param(
        [string[]]$CandidatePaths = @(),
        [switch]$OnlyCandidates
    )

    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in @($CandidatePaths)) {
        if ($candidate -and -not $candidates.Contains([string]$candidate)) {
            $candidates.Add([string]$candidate) | Out-Null
        }
    }
    if (-not $OnlyCandidates) {
        $localBinary = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin\codex.exe'
        if ((Test-Path -LiteralPath $localBinary -PathType Leaf) -and -not $candidates.Contains($localBinary)) {
            $candidates.Add($localBinary) | Out-Null
        }
        foreach ($command in @(Get-Command codex -All -ErrorAction SilentlyContinue)) {
            if ($command.Source -and -not $candidates.Contains([string]$command.Source)) {
                $candidates.Add([string]$command.Source) | Out-Null
            }
        }
    }
    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        try {
            $version = (& $candidate --version 2>&1 | Out-String).Trim()
            if ($LASTEXITCODE -eq 0) {
                return [pscustomobject]@{ Source = $candidate; Version = $version }
            }
        } catch { }
    }
    return $null
}

$required = @(
    "AGENTS.md",
    "CODEX.md",
    "harness.capabilities.json",
    "harness.components.json",
    "hooks.json",
    "docs\auth.md",
    "docs\environment.md",
    "docs\profiles.md",
    "docs\retention.md",
    "docs\context.md",
    "docs\tool-surface.md",
    "docs\runtime.md",
    "docs\verification-gate.md",
    "docs\trace-evals.md",
    "docs\tool-failures.md",
    "docs\skill-surface.md",
    "docs\codex-workflow-core.md",
    "docs\context-budget.md",
    "docs\job-state.md",
    "docs\component-evolution.md",
    "docs\weekly-learning.md",
    "rules\default.rules",
    "scripts\audit-project-harness.ps1",
    "scripts\check-project-docs.ps1",
    "scripts\check-harness-surface.ps1",
    "scripts\init-project-harness.ps1",
    "scripts\codex-hook.ps1",
    "scripts\codex-hook-router.ps1",
    "scripts\codex-stop-log.ps1",
    "scripts\detect-project-test-surface.ps1",
    "scripts\invoke-codex-workflow.ps1",
    "scripts\test-codex-workflow-core.ps1",
    "scripts\new-harness-change.ps1",
    "scripts\new-trace-eval.ps1",
    "scripts\new-session-summary.ps1",
    "scripts\new-agent-run.ps1",
    "scripts\new-job-state.ps1",
    "scripts\new-learning-intake.ps1",
    "scripts\invoke-weekly-harness-learning.ps1",
    "scripts\new-runtime-run.ps1",
    "scripts\invoke-verification-envelope.ps1",
    "scripts\invoke-verification-gate.ps1",
    "scripts\summarize-trace-evals.ps1",
    "scripts\new-tool-failure.ps1",
    "scripts\audit-skill-surface.ps1",
    "scripts\audit-context-budget.ps1",
    "scripts\audit-harness-components.ps1",
    "scripts\new-ablation-run.ps1",
    "scripts\safe-remove.ps1",
    "scripts\verify-global-harness.ps1",
    "scripts\harness-health.ps1",
    "templates\project-harness\project.md",
    "templates\project-harness\testing.md",
    "templates\project-harness\smoke.md",
    "templates\project-harness\observability.md",
    "templates\project-harness\auth.md",
    "templates\project-harness\profiles.md",
    "templates\project-harness\retention.md",
    "templates\project-harness\context.md",
    "templates\project-harness\tool-surface.md",
    "templates\project-harness\runtime.md",
    "templates\project-harness\verification-gate.md",
    "templates\project-harness\trace-evals.md",
    "templates\project-harness\tool-failures.md",
    "templates\project-harness\skill-surface.md",
    "templates\project-harness\context-budget.md",
    "templates\project-harness\job-state.md",
    "templates\project-harness\component-evolution.md",
    "templates\project-harness\harness.capabilities.json",
    "templates\project-harness\harness.components.json",
    "templates\project-harness\code-map.md",
    "templates\project-harness\features.json",
    "templates\project-harness\quality.md",
    "templates\project-harness\reliability.md",
    "templates\project-harness\security.md",
    "templates\project-harness\tech-debt.md",
    "templates\project-harness\major-task-plan.md",
    "templates\project-harness\goal-plan.md",
    "templates\project-harness\harness-change.md",
    "templates\project-harness\agent-task.md",
    "templates\project-harness\evals\README.md",
    "templates\project-harness\evals\prompts.csv",
    "templates\project-harness\evals\tool-evals\README.md",
    "templates\project-harness\evals\tool-evals\cases\tool-selection-smoke.json",
    "templates\project-harness\evals\tool-evals\cases\safety-smoke.json",
    "templates\project-harness\scripts\audit-worktree.ps1",
    "templates\project-harness\scripts\audit-project-harness.ps1",
    "templates\project-harness\scripts\check-all.ps1",
    "templates\project-harness\scripts\check-architecture.ps1",
    "templates\project-harness\scripts\check-features.ps1",
    "templates\project-harness\scripts\check-project-docs.ps1",
    "templates\project-harness\scripts\check-tool-evals.ps1",
    "templates\project-harness\scripts\detect-project-test-surface.ps1",
    "templates\project-harness\scripts\grade-codex-trace-evals.ps1",
    "templates\project-harness\scripts\init-agent-session.ps1",
    "templates\project-harness\scripts\invoke-codex-workflow.ps1",
    "templates\project-harness\scripts\new-goal.ps1",
    "templates\project-harness\scripts\new-harness-change.ps1",
    "templates\project-harness\scripts\new-trace-eval.ps1",
    "templates\project-harness\scripts\new-session-summary.ps1",
    "templates\project-harness\scripts\new-agent-run.ps1",
    "templates\project-harness\scripts\new-job-state.ps1",
    "templates\project-harness\scripts\new-learning-intake.ps1",
    "templates\project-harness\scripts\new-runtime-run.ps1",
    "templates\project-harness\scripts\invoke-verification-gate.ps1",
    "templates\project-harness\scripts\invoke-verification-envelope.ps1",
    "templates\project-harness\scripts\summarize-trace-evals.ps1",
    "templates\project-harness\scripts\new-tool-failure.ps1",
    "templates\project-harness\scripts\audit-skill-surface.ps1",
    "templates\project-harness\scripts\audit-context-budget.ps1",
    "templates\project-harness\scripts\audit-harness-components.ps1",
    "templates\project-harness\scripts\new-ablation-run.ps1",
    "templates\project-harness\scripts\new-review.ps1",
    "templates\project-harness\scripts\new-run.ps1",
    "templates\project-harness\scripts\new-smoke-run.ps1",
    "templates\project-harness\scripts\run-codex-trace-evals.ps1",
    "templates\project-harness\scripts\smoke-canvas.ps1",
    "templates\project-harness\scripts\smoke-persistence.ps1",
    "templates\project-harness\scripts\smoke-routing.ps1",
    "templates\project-harness\scripts\safe-remove.ps1",
    "templates\project-harness\scripts\update-project-state.ps1",
    "templates\project-harness\scripts\verify-harness.ps1",
    "harness-evals\run-harness-evals.ps1",
    "harness-evals\run-trace-evals.ps1",
    "harness-evals\grade-trace-evals.ps1",
    "harness-evals\test-trace-evals-v3.ps1",
    "harness-evals\test-verification-gate.ps1",
    "harness-evals\test-verification-envelope.ps1",
    "harness-evals\test-project-harness-optimizer.ps1",
    "harness-evals\test-weekly-harness-learning.ps1",
    "harness-evals\trace-evals\README.md",
    "harness-evals\trace-evals\prompts.csv",
    "harness-evals\cases\docs-sync\README.md",
    "harness-evals\cases\project-scaffold\README.md",
    "harness-evals\cases\hook-privacy\README.md",
    "harness-evals\cases\maturity-layer\README.md",
    "harness-evals\cases\optimizer-workflow-routing\README.md",
    "harness-evals\cases\article-source-resolver\README.md",
    "harness-evals\cases\article-source-resolver\fixtures\classic.html",
    "harness-evals\cases\article-source-resolver\fixtures\classic-utf8.html",
    "harness-evals\cases\article-source-resolver\fixtures\ssr.html",
    "harness-evals\cases\article-source-resolver\fixtures\generic.html",
    "harness-evals\cases\article-source-resolver\fixtures\generic-main.html",
    "harness-evals\cases\article-source-resolver\fixtures\jsonld.html",
    "harness-evals\cases\article-source-resolver\fixtures\deleted.html",
    "harness-evals\cases\article-source-resolver\fixtures\challenge.html",
    "harness-evals\cases\web-source-resolver\README.md",
    "harness-evals\cases\web-source-resolver\fixtures\web-body.html",
    "harness-evals\cases\web-source-resolver\fixtures\client-shell.html",
    "harness-evals\cases\web-source-resolver\fixtures\documentation.html",
    "harness-evals\cases\web-source-resolver\fixtures\data.json",
    "harness-evals\cases\web-source-resolver\fixtures\feed.xml",
    "harness-evals\cases\web-source-resolver\fixtures\notes.txt",
    "harness-evals\cases\web-source-resolver\fixtures\tiny.pdf",
    "harness-evals\cases\safe-remove\README.md",
    "harness-evals\cases\smoke-record\README.md",
    "harness-evals\test-article-source-resolver.ps1",
    "harness-evals\test-web-source-resolver.ps1",
    "skills\project-harness-optimizer\SKILL.md",
    "skills\harness-orchestrator\SKILL.md",
    "skills\harness-orchestrator\references\workflow-graph-contract.md",
    "skills\web-source-resolver\SKILL.md",
    "skills\web-source-resolver\agents\openai.yaml",
    "skills\web-source-resolver\references\routing-contract.md",
    "skills\web-source-resolver\scripts\resolve-web-source.ps1",
    "skills\article-source-resolver\SKILL.md",
    "skills\article-source-resolver\agents\openai.yaml",
    "skills\article-source-resolver\references\evidence-contract.md",
    "skills\article-source-resolver\scripts\resolve-article-source.ps1",
    "skills\article-source-resolver\scripts\resolve_article_source.py",
    "agents\explorer.toml",
    "agents\reviewer.toml",
    "agents\docs-researcher.toml",
    "agents\planner.toml",
    "agents\architect.toml",
    "agents\tester.toml",
    "agents\e2e-runner.toml",
    "agents\build-error-resolver.toml",
    "agents\security-reviewer.toml",
    "agents\doc-updater.toml",
    "agents\harness-auditor.toml",
    "agents\regression-miner.toml",
    "agents\refactor-cleaner.toml"
)

$missing = @()
foreach ($rel in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $codexHomePath $rel))) {
        $missing += $rel
    }
}

if ($missing.Count -gt 0) {
    throw "Missing global harness files: $($missing -join ', ')"
}

$configPath = Join-Path $codexHomePath "config.toml"
$configPresent = Test-Path -LiteralPath $configPath -PathType Leaf
$config = ""
$configMcpNames = @()
$configMcpSubsections = @()

if ($configPresent -and $python) {
    $script = @'
from pathlib import Path
import tomllib
path = Path(r"__CONFIG__")
tomllib.loads(path.read_text(encoding="utf-8"))
print("toml-ok")
'@
    $script = $script.Replace("__CONFIG__", $configPath.Replace('\', '\\'))
    $tmp = Join-Path $env:TEMP ("codex-global-harness-verify-" + [guid]::NewGuid().ToString("N") + ".py")
    try {
        Set-Content -LiteralPath $tmp -Value $script -Encoding UTF8
        & $python.Source $tmp | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "config.toml TOML parse failed." }
    } finally {
        if (Test-Path -LiteralPath $tmp -PathType Leaf) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
}

foreach ($jsonPath in @(
    "harness.capabilities.json",
    "harness.components.json",
    "hooks.json",
    "templates\project-harness\harness.capabilities.json",
    "templates\project-harness\harness.components.json",
    "templates\project-harness\features.json"
)) {
    try {
        Get-Content -LiteralPath (Join-Path $codexHomePath $jsonPath) -Raw | ConvertFrom-Json | Out-Null
    } catch {
        throw "$jsonPath JSON parse error: $($_.Exception.Message)"
    }
}

if ($configPresent) {
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
    $rootConfig = [regex]::Split($config, '(?m)^\s*\[')[0]
    if ($rootConfig -match '(?m)^\s*model\s*=' -or
        $rootConfig -match '(?m)^\s*(model_reasoning_effort|reasoning_effort)\s*=') {
        throw 'Global config pins model or reasoning effort; leave both unset so Codex can adapt to the task.'
    }
    $configMcpNames = Get-McpServerNames -Config $config
    $configMcpSubsections = Get-McpSubsections -Config $config
    foreach ($name in @("github", "context7", "exa", "memory", "playwright", "sequential-thinking")) {
        if ($config -notmatch "(?m)^\[mcp_servers\.$([regex]::Escape($name))\]") {
            throw "Missing expected MCP server: $name"
        }
    }

    foreach ($featureName in @("hooks", "goals", "multi_agent")) {
        $featureMatch = [regex]::Match(
            $config,
            "(?m)^\s*$([regex]::Escape($featureName))\s*=\s*(true|false)\s*(?:#.*)?$"
        )
        if ($featureMatch.Success -and $featureMatch.Groups[1].Value -eq "false") {
            throw "Stable default feature is explicitly disabled: $featureName=false"
        }
    }
    if ($config -match '(?m)^\s*plugin_hooks\s*=') {
        throw "Found obsolete plugin_hooks feature flag in active global config."
    }
    if ($config -match 'codex_hooks') {
        throw "Found deprecated codex_hooks in active global config."
    }
    if ($config -match 'codex-stop-log\.ps1' -or $config -match 'codex-hook-router\.ps1') {
        throw "Legacy inline hook wiring remains in config.toml; use hooks.json as the single user-level hook source."
    }
}

$codexCli = Resolve-CodexCommand
if (-not $codexCli) {
    throw 'No executable Codex CLI candidate passed the --version probe.'
}
$fallbackFixture = Join-Path $env:TEMP ('codex-cli-fail-' + [guid]::NewGuid().ToString('N') + '.cmd')
try {
    [System.IO.File]::WriteAllText($fallbackFixture, "@echo off`r`nexit /b 7`r`n", (New-Object System.Text.ASCIIEncoding))
    $fallbackProbe = Resolve-CodexCommand -CandidatePaths @($fallbackFixture, $codexCli.Source) -OnlyCandidates
    if (-not $fallbackProbe -or $fallbackProbe.Source -ne $codexCli.Source) {
        throw 'Codex CLI resolver did not skip a failing candidate.'
    }
} finally {
    if (Test-Path -LiteralPath $fallbackFixture -PathType Leaf) {
        Remove-Item -LiteralPath $fallbackFixture -Force -ErrorAction SilentlyContinue
    }
}
$previousCodexHome = $env:CODEX_HOME
try {
    $env:CODEX_HOME = $codexHomePath
    $cliConfigProbe = (& $codexCli.Source features list 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        $safeProbe = ($cliConfigProbe -replace '[\r\n]+', ' ')
        if ($safeProbe.Length -gt 600) { $safeProbe = $safeProbe.Substring(0, 600) + '...' }
        throw "Codex CLI rejected the selected CODEX_HOME config: $safeProbe"
    }
} finally {
    if ($null -eq $previousCodexHome) {
        Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue
    } else {
        $env:CODEX_HOME = $previousCodexHome
    }
}

$hooksPath = Join-Path $codexHomePath "hooks.json"
$hooks = Get-Content -LiteralPath $hooksPath -Raw -Encoding UTF8 | ConvertFrom-Json
$hookDefinitionSha256 = (Get-FileHash -LiteralPath $hooksPath -Algorithm SHA256).Hash.ToLowerInvariant()
$requiredHookEvents = @("SessionStart", "PreToolUse", "PermissionRequest", "PostToolUse", "PreCompact", "PostCompact", "UserPromptSubmit", "SubagentStart", "SubagentStop", "Stop")
foreach ($eventName in $requiredHookEvents) {
    if ($hooks.hooks.PSObject.Properties.Name -notcontains $eventName) {
        throw "hooks.json is missing required lifecycle event: $eventName"
    }
}
foreach ($eventProperty in $hooks.hooks.PSObject.Properties) {
    $eventName = $eventProperty.Name
    foreach ($group in @($eventProperty.Value)) {
        foreach ($hook in @($group.hooks)) {
            if ([string]$hook.command -notmatch 'CODEX_HOME' -or [string]$hook.commandWindows -notmatch 'CODEX_HOME') {
                throw "Hook wiring for $eventName does not honor CODEX_HOME on both command paths."
            }
            if ([string]$hook.command -notmatch [regex]::Escape("-Event $eventName") -or
                [string]$hook.commandWindows -notmatch [regex]::Escape("-Event $eventName")) {
                throw "Hook wiring for $eventName does not route to its matching event."
            }
        }
    }
}

$agentNames = New-Object System.Collections.Generic.List[string]
foreach ($agentFile in @(Get-ChildItem -LiteralPath (Join-Path $codexHomePath "agents") -File -Filter "*.toml" | Sort-Object Name)) {
    $agentConfig = Get-Content -LiteralPath $agentFile.FullName -Raw -Encoding UTF8
    $nameMatch = [regex]::Match($agentConfig, '(?m)^\s*name\s*=\s*"([^"]+)"\s*$')
    $descriptionMatch = [regex]::Match($agentConfig, '(?m)^\s*description\s*=\s*"([^"]+)"\s*$')
    if (-not $nameMatch.Success -or -not $descriptionMatch.Success -or $agentConfig -notmatch '(?m)^\s*developer_instructions\s*=') {
        throw "Custom agent file is missing name, description, or developer_instructions: $($agentFile.Name)"
    }
    if ($agentConfig -match '(?m)^\s*(model|model_reasoning_effort|reasoning_effort)\s*=') {
        throw "Reusable custom agent pins model or reasoning effort instead of allowing adaptive selection: $($agentFile.Name)"
    }
    $expectedName = [System.IO.Path]::GetFileNameWithoutExtension($agentFile.Name).Replace("-", "_")
    $agentName = $nameMatch.Groups[1].Value
    if ($agentName -ne $expectedName) {
        throw "Custom agent name does not match its portable filename convention: $($agentFile.Name) -> $agentName"
    }
    if ($agentNames.Contains($agentName)) {
        throw "Duplicate custom agent name: $agentName"
    }
    $agentNames.Add($agentName) | Out-Null
}

$automationTemplatePath = Join-Path $codexHomePath 'automations\harness\automation.toml.template'
$automationTemplate = Get-Content -LiteralPath $automationTemplatePath -Raw -Encoding UTF8
if ($automationTemplate -match '(?m)^\s*(model|model_reasoning_effort|reasoning_effort)\s*=') {
    throw 'Weekly automation template pins model or reasoning effort.'
}
if ($automationTemplate -notmatch '(?m)^\s*execution_environment\s*=\s*"worktree"\s*$') {
    throw 'Weekly automation template must use worktree isolation.'
}
$weeklyAutomationPath = Join-Path $codexHomePath 'automations\weekly-codex-harness-health\automation.toml'
if (Test-Path -LiteralPath $weeklyAutomationPath -PathType Leaf) {
    $weeklyAutomation = Get-Content -LiteralPath $weeklyAutomationPath -Raw -Encoding UTF8
    $automationModel = [regex]::Match($weeklyAutomation, '(?m)^\s*model\s*=\s*"([^"]+)"\s*$')
    $automationReasoning = [regex]::Match($weeklyAutomation, '(?m)^\s*reasoning_effort\s*=\s*"([^"]+)"\s*$')
    if ($automationModel.Success -and $automationModel.Groups[1].Value -ne 'auto') {
        throw 'Active weekly automation pins a concrete model instead of using the app automatic sentinel.'
    }
    if ($automationReasoning.Success -and $automationReasoning.Groups[1].Value -ne 'none') {
        throw 'Active weekly automation pins reasoning effort instead of using the app no-override sentinel.'
    }
    if ($weeklyAutomation -notmatch '(?m)^\s*execution_environment\s*=\s*"worktree"\s*$') {
        throw 'Active weekly automation must use worktree isolation.'
    }
}

foreach ($scriptPath in @(
    "scripts\audit-project-harness.ps1",
    "scripts\check-project-docs.ps1",
    "scripts\check-harness-surface.ps1",
    "scripts\init-project-harness.ps1",
    "scripts\codex-hook.ps1",
    "scripts\codex-hook-router.ps1",
    "scripts\codex-stop-log.ps1",
    "scripts\detect-project-test-surface.ps1",
    "scripts\invoke-codex-workflow.ps1",
    "scripts\test-codex-workflow-core.ps1",
    "scripts\new-harness-change.ps1",
    "scripts\new-trace-eval.ps1",
    "scripts\new-session-summary.ps1",
    "scripts\new-agent-run.ps1",
    "scripts\new-job-state.ps1",
    "scripts\new-learning-intake.ps1",
    "scripts\invoke-weekly-harness-learning.ps1",
    "scripts\new-runtime-run.ps1",
    "scripts\invoke-verification-envelope.ps1",
    "scripts\invoke-verification-gate.ps1",
    "scripts\summarize-trace-evals.ps1",
    "scripts\new-tool-failure.ps1",
    "scripts\audit-skill-surface.ps1",
    "scripts\audit-context-budget.ps1",
    "scripts\audit-harness-components.ps1",
    "scripts\new-ablation-run.ps1",
    "scripts\safe-remove.ps1",
    "scripts\verify-global-harness.ps1",
    "scripts\harness-health.ps1",
    "skills\article-source-resolver\scripts\resolve-article-source.ps1",
    "skills\web-source-resolver\scripts\resolve-web-source.ps1",
    "harness-evals\run-harness-evals.ps1",
    "harness-evals\test-article-source-resolver.ps1",
    "harness-evals\test-web-source-resolver.ps1",
    "harness-evals\run-trace-evals.ps1",
    "harness-evals\grade-trace-evals.ps1",
    "harness-evals\test-trace-evals-v3.ps1",
    "harness-evals\test-verification-gate.ps1",
    "harness-evals\test-verification-envelope.ps1",
    "harness-evals\test-project-harness-optimizer.ps1",
    "harness-evals\test-weekly-harness-learning.ps1",
    "templates\project-harness\scripts\audit-worktree.ps1",
    "templates\project-harness\scripts\audit-project-harness.ps1",
    "templates\project-harness\scripts\check-all.ps1",
    "templates\project-harness\scripts\check-architecture.ps1",
    "templates\project-harness\scripts\check-features.ps1",
    "templates\project-harness\scripts\check-project-docs.ps1",
    "templates\project-harness\scripts\check-tool-evals.ps1",
    "templates\project-harness\scripts\detect-project-test-surface.ps1",
    "templates\project-harness\scripts\grade-codex-trace-evals.ps1",
    "templates\project-harness\scripts\init-agent-session.ps1",
    "templates\project-harness\scripts\invoke-codex-workflow.ps1",
    "templates\project-harness\scripts\new-goal.ps1",
    "templates\project-harness\scripts\new-harness-change.ps1",
    "templates\project-harness\scripts\new-trace-eval.ps1",
    "templates\project-harness\scripts\new-session-summary.ps1",
    "templates\project-harness\scripts\new-agent-run.ps1",
    "templates\project-harness\scripts\new-job-state.ps1",
    "templates\project-harness\scripts\new-learning-intake.ps1",
    "templates\project-harness\scripts\new-runtime-run.ps1",
    "templates\project-harness\scripts\invoke-verification-gate.ps1",
    "templates\project-harness\scripts\invoke-verification-envelope.ps1",
    "templates\project-harness\scripts\summarize-trace-evals.ps1",
    "templates\project-harness\scripts\new-tool-failure.ps1",
    "templates\project-harness\scripts\audit-skill-surface.ps1",
    "templates\project-harness\scripts\audit-context-budget.ps1",
    "templates\project-harness\scripts\audit-harness-components.ps1",
    "templates\project-harness\scripts\new-ablation-run.ps1",
    "templates\project-harness\scripts\new-review.ps1",
    "templates\project-harness\scripts\new-run.ps1",
    "templates\project-harness\scripts\new-smoke-run.ps1",
    "templates\project-harness\scripts\run-codex-trace-evals.ps1",
    "templates\project-harness\scripts\smoke-canvas.ps1",
    "templates\project-harness\scripts\smoke-persistence.ps1",
    "templates\project-harness\scripts\smoke-routing.ps1",
    "templates\project-harness\scripts\safe-remove.ps1",
    "templates\project-harness\scripts\update-project-state.ps1",
    "templates\project-harness\scripts\verify-harness.ps1"
)) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $codexHomePath $scriptPath),
        [ref]$tokens,
        [ref]$errors
    ) | Out-Null
    if ($errors.Count -gt 0) {
        $messages = $errors | ForEach-Object { $_.Message }
        throw "$scriptPath syntax errors: $($messages -join '; ')"
    }
}

if ($python) {
    $resolverPython = Join-Path $codexHomePath "skills\article-source-resolver\scripts\resolve_article_source.py"
    $astCheck = "import ast,pathlib; ast.parse(pathlib.Path(r'" + $resolverPython.Replace("'", "''") + "').read_text(encoding='utf-8'))"
    & $python.Source -c $astCheck
    if ($LASTEXITCODE -ne 0) {
        throw "Article source resolver Python syntax validation failed."
    }
}

$runtimeSkillFiles = @(Get-ChildItem -LiteralPath (Join-Path $codexHomePath "skills") -Directory -Force |
    ForEach-Object { Join-Path $_.FullName "SKILL.md" } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
foreach ($skillPath in $runtimeSkillFiles) {
    $bytes = [System.IO.File]::ReadAllBytes($skillPath)
    if ($bytes.Length -lt 3 -or $bytes[0] -ne 0x2D -or $bytes[1] -ne 0x2D -or $bytes[2] -ne 0x2D) {
        throw "Skill must start with --- in UTF-8 without BOM: $skillPath"
    }
    $skillText = Get-Content -LiteralPath $skillPath -Raw -Encoding UTF8
    $frontmatter = [regex]::Match($skillText, '\A---\r?\n(?<body>[\s\S]*?)\r?\n---(?:\r?\n|$)')
    if (-not $frontmatter.Success) {
        throw "Malformed skill frontmatter: $skillPath"
    }
    $metadata = $frontmatter.Groups["body"].Value
    $name = [regex]::Match($metadata, '(?m)^name:\s*\S+')
    $description = [regex]::Match($metadata, '(?m)^description:\s*\S+')
    if (-not $name.Success -or -not $description.Success) {
        throw "Skill name or description missing: $skillPath"
    }
}

if (-not $rg -and -not (Test-Path -LiteralPath $bundledRg)) {
    throw "rg not found on PATH and bundled fallback missing."
}

[ordered]@{
    status = "success"
    summary = "Global Codex harness verified."
    codex_home = $codexHomePath
    checked = $required
    config_present = $configPresent
    mcp_servers = $configMcpNames
    mcp_subsections = $configMcpSubsections
    codex_cli_version = $codexCli.Version
    behavior_evals_executed = $false
    hooks = @{
        enabled = $true
        source = "hooks.json"
        router = "scripts\codex-hook.ps1"
        definition_sha256 = $hookDefinitionSha256
        trust = "review-with-codex-hooks-command-after-definition-change"
    }
    custom_agents = $agentNames.ToArray()
    skill_files_checked = $runtimeSkillFiles.Count
} | ConvertTo-Json -Depth 8 -Compress
