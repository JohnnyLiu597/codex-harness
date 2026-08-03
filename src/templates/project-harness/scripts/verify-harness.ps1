param(
    [switch]$Fast
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$python = Get-Command python -ErrorAction SilentlyContinue
$rg = Get-Command rg -ErrorAction SilentlyContinue
$bundledRg = "$env:LOCALAPPDATA\OpenAI\Codex\bin\rg.exe"

$required = @(
    "AGENTS.md", "mission.md", "CONTEXT.md", "MEMORY.md",
    "harness.capabilities.json", "harness.components.json",
    "docs\project.md", "docs\architecture.md", "docs\code-map.md", "docs\features.json",
    "docs\commands.md", "docs\testing.md", "docs\smoke.md", "docs\loop.md", "docs\quality.md",
    "docs\reliability.md", "docs\security.md", "docs\tech-debt.md", "docs\observability.md",
    "docs\auth.md", "docs\profiles.md", "docs\retention.md",
    "docs\context.md", "docs\tool-surface.md", "docs\runtime.md", "docs\verification-gate.md",
    "docs\trace-evals.md", "docs\tool-failures.md", "docs\skill-surface.md",
    "docs\context-budget.md", "docs\job-state.md", "docs\component-evolution.md",
    "evals\README.md", "evals\prompts.csv", "evals\tool-evals\README.md",
    "evals\tool-evals\cases\tool-selection-smoke.json", "evals\tool-evals\cases\safety-smoke.json",
    "artifacts\templates\major-task-plan.md", "artifacts\templates\goal-plan.md",
    "artifacts\templates\harness-change.md",
    "artifacts\templates\agent-task.md",
    ".codex\rules\default.rules",
    "scripts\audit-worktree.ps1", "scripts\audit-project-harness.ps1", "scripts\check-all.ps1", "scripts\check-architecture.ps1",
    "scripts\check-features.ps1", "scripts\check-project-docs.ps1", "scripts\check-tool-evals.ps1",
    "scripts\grade-codex-trace-evals.ps1", "scripts\init-agent-session.ps1", "scripts\new-goal.ps1",
    "scripts\new-harness-change.ps1", "scripts\new-trace-eval.ps1", "scripts\new-review.ps1", "scripts\new-run.ps1",
    "scripts\new-session-summary.ps1", "scripts\new-agent-run.ps1", "scripts\new-job-state.ps1", "scripts\new-learning-intake.ps1",
    "scripts\new-runtime-run.ps1",
    "scripts\invoke-verification-gate.ps1", "scripts\invoke-verification-envelope.ps1",
    "scripts\summarize-trace-evals.ps1", "scripts\new-tool-failure.ps1", "scripts\audit-skill-surface.ps1",
    "scripts\audit-context-budget.ps1", "scripts\audit-harness-components.ps1", "scripts\new-ablation-run.ps1",
    "scripts\new-smoke-run.ps1", "scripts\run-codex-trace-evals.ps1", "scripts\smoke-canvas.ps1",
    "scripts\smoke-persistence.ps1", "scripts\smoke-routing.ps1", "scripts\safe-remove.ps1",
    "scripts\update-project-state.ps1", "scripts\verify-harness.ps1"
)

$missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $root $_)) })
if ($missing.Count -gt 0) { throw "Missing harness files: $($missing -join ', ')" }

if ($python) {
    $tomlFiles = @(".codex\config.toml", ".codex\environments\environment.toml") | Where-Object { Test-Path -LiteralPath (Join-Path $root $_) }
    if ($tomlFiles.Count -gt 0) {
        $filesLiteral = "[" + (($tomlFiles | ForEach-Object { "r'" + ($_ -replace '\\','/') + "'" }) -join ", ") + "]"
        $escapedRoot = $root.Replace("'", "''")
        $code = "from pathlib import Path; import tomllib; root=Path(r'''$escapedRoot'''); files=$filesLiteral; [tomllib.loads((root / f).read_text(encoding='utf-8')) for f in files]; print('toml-ok')"
        & $python.Source -c $code | Out-Null
    }
}

foreach ($scriptPath in @($required | Where-Object { $_ -like "scripts\*.ps1" })) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $scriptPath), [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        $messages = $errors | ForEach-Object { $_.Message }
        throw "$scriptPath syntax errors: $($messages -join '; ')"
    }
}

$jsonFiles = @("harness.capabilities.json", "harness.components.json", "docs\features.json")
foreach ($jsonFile in $jsonFiles) {
    try {
        Get-Content -LiteralPath (Join-Path $root $jsonFile) -Raw | ConvertFrom-Json | Out-Null
    } catch {
        throw "$jsonFile JSON parse error: $($_.Exception.Message)"
    }
}

& (Join-Path $root "scripts\audit-context-budget.ps1") -ProjectRoot $root | Out-Null
& (Join-Path $root "scripts\audit-harness-components.ps1") -ProjectRoot $root | Out-Null

if (-not $rg -and -not (Test-Path -LiteralPath $bundledRg)) { throw "rg not found on PATH and bundled fallback missing." }

[ordered]@{
    status = "success"
    summary = "Harness scaffold and script syntax verified."
    next_actions = @("Use docs\testing.md to choose the lowest sufficient L0-L5 verification layer.", "Reserve scripts\check-all.ps1 and -Smoke for L5/high-risk or release-handoff work.")
    artifacts = @($required | ForEach-Object { Join-Path $root $_ })
} | ConvertTo-Json -Depth 5 -Compress
