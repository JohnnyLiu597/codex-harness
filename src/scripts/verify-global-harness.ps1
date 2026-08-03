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

$required = @(
    "AGENTS.md",
    "CODEX.md",
    "harness.capabilities.json",
    "config.toml",
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
    "rules\default.rules",
    "scripts\audit-project-harness.ps1",
    "scripts\check-project-docs.ps1",
    "scripts\check-harness-surface.ps1",
    "scripts\init-project-harness.ps1",
    "scripts\codex-hook-router.ps1",
    "scripts\codex-stop-log.ps1",
    "scripts\detect-project-test-surface.ps1",
    "scripts\invoke-codex-workflow.ps1",
    "scripts\test-codex-workflow-core.ps1",
    "scripts\new-harness-change.ps1",
    "scripts\new-trace-eval.ps1",
    "scripts\new-session-summary.ps1",
    "scripts\new-agent-run.ps1",
    "scripts\new-learning-intake.ps1",
    "scripts\new-runtime-run.ps1",
    "scripts\invoke-verification-gate.ps1",
    "scripts\summarize-trace-evals.ps1",
    "scripts\new-tool-failure.ps1",
    "scripts\audit-skill-surface.ps1",
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
    "templates\project-harness\harness.capabilities.json",
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
    "templates\project-harness\scripts\new-learning-intake.ps1",
    "templates\project-harness\scripts\new-runtime-run.ps1",
    "templates\project-harness\scripts\invoke-verification-gate.ps1",
    "templates\project-harness\scripts\summarize-trace-evals.ps1",
    "templates\project-harness\scripts\new-tool-failure.ps1",
    "templates\project-harness\scripts\audit-skill-surface.ps1",
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

if ($python) {
    $script = @'
from pathlib import Path
import tomllib
root = Path(r"__ROOT__")
tomllib.loads((root / "config.toml").read_text(encoding="utf-8"))
print("toml-ok")
'@
    $script = $script.Replace("__ROOT__", $codexHomePath.Replace('\', '\\'))
    $tmp = Join-Path $env:TEMP ("codex-global-harness-verify-" + [guid]::NewGuid().ToString("N") + ".py")
    Set-Content -LiteralPath $tmp -Value $script -Encoding UTF8
    & $python.Source $tmp | Out-Null
    Remove-Item -LiteralPath $tmp -Force
}

foreach ($jsonPath in @(
    "harness.capabilities.json",
    "templates\project-harness\harness.capabilities.json",
    "templates\project-harness\features.json"
)) {
    try {
        Get-Content -LiteralPath (Join-Path $codexHomePath $jsonPath) -Raw | ConvertFrom-Json | Out-Null
    } catch {
        throw "$jsonPath JSON parse error: $($_.Exception.Message)"
    }
}

$config = Get-Content -LiteralPath (Join-Path $codexHomePath "config.toml") -Raw
$configMcpNames = Get-McpServerNames -Config $config
$configMcpSubsections = Get-McpSubsections -Config $config
foreach ($name in @("github", "context7", "exa", "memory", "playwright", "sequential-thinking")) {
    if ($config -notmatch "(?m)^\[mcp_servers\.$([regex]::Escape($name))\]") {
        throw "Missing expected MCP server: $name"
    }
}

if ($config -notmatch '(?m)^hooks\s*=\s*true') {
    throw "Feature hooks=true is not enabled."
}
if ($config -notmatch '(?m)^plugin_hooks\s*=\s*true') {
    throw "Feature plugin_hooks=true is not enabled."
}
if ($config -notmatch '(?m)^goals\s*=\s*true') {
    throw "Feature goals=true is not enabled."
}
if ($config -notmatch '\[\[hooks\.Stop\]\]' -or $config -notmatch 'codex-stop-log\.ps1') {
    throw "Stop hook is not wired to codex-stop-log.ps1."
}
if ($config -match 'codex_hooks') {
    throw "Found deprecated codex_hooks in active global config."
}

foreach ($scriptPath in @(
    "scripts\audit-project-harness.ps1",
    "scripts\check-project-docs.ps1",
    "scripts\check-harness-surface.ps1",
    "scripts\init-project-harness.ps1",
    "scripts\codex-hook-router.ps1",
    "scripts\codex-stop-log.ps1",
    "scripts\detect-project-test-surface.ps1",
    "scripts\invoke-codex-workflow.ps1",
    "scripts\test-codex-workflow-core.ps1",
    "scripts\new-harness-change.ps1",
    "scripts\new-trace-eval.ps1",
    "scripts\new-session-summary.ps1",
    "scripts\new-agent-run.ps1",
    "scripts\new-learning-intake.ps1",
    "scripts\new-runtime-run.ps1",
    "scripts\invoke-verification-gate.ps1",
    "scripts\summarize-trace-evals.ps1",
    "scripts\new-tool-failure.ps1",
    "scripts\audit-skill-surface.ps1",
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
    "templates\project-harness\scripts\new-learning-intake.ps1",
    "templates\project-harness\scripts\new-runtime-run.ps1",
    "templates\project-harness\scripts\invoke-verification-gate.ps1",
    "templates\project-harness\scripts\summarize-trace-evals.ps1",
    "templates\project-harness\scripts\new-tool-failure.ps1",
    "templates\project-harness\scripts\audit-skill-surface.ps1",
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

$workflowCoreTest = Join-Path $codexHomePath "scripts\test-codex-workflow-core.ps1"
& $workflowCoreTest -CodexHome $codexHomePath | Out-Null

if (-not $rg -and -not (Test-Path -LiteralPath $bundledRg)) {
    throw "rg not found on PATH and bundled fallback missing."
}

[ordered]@{
    status = "success"
    summary = "Global Codex harness verified."
    codex_home = $codexHomePath
    checked = $required
    mcp_servers = $configMcpNames
    mcp_subsections = $configMcpSubsections
    hooks = @{
        enabled = $true
        stop_log = "scripts\codex-stop-log.ps1"
    }
} | ConvertTo-Json -Depth 8 -Compress
