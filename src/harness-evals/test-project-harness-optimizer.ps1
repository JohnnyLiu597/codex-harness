param(
    [string]$CodexHome = "$env:USERPROFILE\.codex"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $CodexHome).Path
$skillRoot = Join-Path $root "skills\project-harness-optimizer"
$skillPath = Join-Path $skillRoot "SKILL.md"
$identityPath = Join-Path $skillRoot "references\project-identity-gate.md"
$identityCasesPath = Join-Path $root "harness-evals\cases\project-identity-gate\cases.json"
$checks = New-Object System.Collections.Generic.List[object]

function Add-Check {
    param([string]$Name, [string]$Detail)
    $checks.Add([pscustomobject]@{ name = $Name; status = "passed"; detail = $Detail }) | Out-Null
}

if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) {
    throw "project-harness-optimizer SKILL.md missing: $skillPath"
}
if (-not (Test-Path -LiteralPath (Join-Path $root "docs\weekly-learning.md") -PathType Leaf)) {
    throw "Weekly learning policy missing."
}

$skill = Get-Content -LiteralPath $skillPath -Raw -Encoding UTF8
$skillLines = @(Get-Content -LiteralPath $skillPath -Encoding UTF8).Count
$skillBytes = (Get-Item -LiteralPath $skillPath).Length
if ($skillBytes -gt 16000 -or $skillLines -gt 500) {
    throw "Optimizer exceeds progressive-disclosure budget: bytes=$skillBytes lines=$skillLines"
}
Add-Check -Name "progressive-disclosure-budget" -Detail "bytes=$skillBytes lines=$skillLines"

if ($skill -notmatch '(?s)^---\s*\r?\nname:\s*project-harness-optimizer\s*\r?\ndescription:.+?\r?\n---') {
    throw "Optimizer frontmatter is invalid or incomplete."
}
Add-Check -Name "frontmatter" -Detail "name and trigger description present"

foreach ($reference in @(
    "references\maintenance-and-safety.md",
    "references\workflow-state-and-evidence.md",
    "references\project-identity-gate.md",
    "references\project-scaffold.md",
    "agents\openai.yaml"
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $skillRoot $reference) -PathType Leaf)) {
        throw "Optimizer resource missing: $reference"
    }
}
Add-Check -Name "resources" -Detail "maintenance, identity, workflow, scaffold, and UI metadata present"

$globalAgents = Get-Content -LiteralPath (Join-Path $root "AGENTS.md") -Raw -Encoding UTF8
$identityReference = Get-Content -LiteralPath $identityPath -Raw -Encoding UTF8
foreach ($required in @(
    "Project Identity Gate",
    "Observed",
    "Inferred",
    "Unknown",
    "at most three questions",
    "architecture or",
    "organizational",
    "final outcome and success criteria",
    "generated evidence",
    "cannot validate the premise",
    "do not write files",
    "at most one read-only explorer",
    'generic "continue" or "do it" does not waive'
)) {
    if ($identityReference -notmatch [regex]::Escape($required)) {
        throw "Project identity reference is missing a required invariant: $required"
    }
}
foreach ($required in @(
    "Project Identity Gate",
    "Files generated during the current task cannot confirm",
    "at most three questions",
    "outcome, success criteria, and allowed change scope",
    "write files, extract or reorganize assets",
    "Before a project identity lock, use at most one read-only explorer"
)) {
    if ($globalAgents -notmatch [regex]::Escape($required)) {
        throw "Global AGENTS.md is missing project identity guidance: $required"
    }
}
if ($skill.IndexOf("Project Identity Gate", [System.StringComparison]::Ordinal) -lt 0 -or
    $skill.IndexOf("Project Identity Gate", [System.StringComparison]::Ordinal) -gt $skill.IndexOf("Maintenance Lanes", [System.StringComparison]::Ordinal)) {
    throw "Project Identity Gate must precede maintenance-lane selection in the optimizer."
}
Add-Check -Name "project-identity-contract" -Detail "read-only discovery, confidence, brainstorming, identity lock, correction, and delegation fences present"

if (-not (Test-Path -LiteralPath $identityCasesPath -PathType Leaf)) {
    throw "Project identity regression cases missing: $identityCasesPath"
}
$identityCases = Get-Content -LiteralPath $identityCasesPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($identityCases.schema -ne "project-identity-gate-cases-v1" -or @($identityCases.cases).Count -ne 3) {
    throw "Project identity regression case schema or count is invalid."
}
foreach ($case in @($identityCases.cases)) {
    if ($case.expected_action -ne "ask-before-write" -or $case.expected_confidence -eq "high") {
        throw "Identity case does not fail closed before writes: $($case.id)"
    }
    if (@($case.required_questions).Count -ne 3) {
        throw "Identity case must cover purpose, architecture, and final outcome: $($case.id)"
    }
    foreach ($prohibited in @("infer-project-purpose", "write-roadmap")) {
        if ($prohibited -notin @($case.prohibited_actions)) {
            throw "Identity case lacks prohibited action '$prohibited': $($case.id)"
        }
    }
}
Add-Check -Name "project-identity-regressions" -Detail "document vault, template library, and asset collection cases fail closed before writes"

$workflowReference = Get-Content -LiteralPath (Join-Path $skillRoot "references\workflow-state-and-evidence.md") -Raw -Encoding UTF8
foreach ($required in @(
    "standalone TOML",
    "name",
    "description",
    "developer_instructions",
    "model_reasoning_effort",
    "spawn-time override",
    "fan-out/fan-in",
    "checkpoint"
)) {
    if ($workflowReference -notmatch [regex]::Escape($required)) {
        throw "Optimizer workflow reference is missing portable custom-agent guidance: $required"
    }
}
Add-Check -Name "custom-agent-contract" -Detail "standalone schema, adaptive capability, graph, and checkpoint guidance present"

foreach ($required in @(
    "Runtime Hotfix",
    "Source Release",
    "Audit Only",
    "Project Identity Gate",
    "hooks.json",
    "audit-context-budget.ps1",
    "new-agent-run.ps1",
    "new-job-state.ps1",
    "invoke-verification-envelope.ps1",
    "invoke-verification-gate.ps1",
    "tool_use_id",
    "declared policy",
    "isolated staging",
    "-InstallRuntime",
    "roll back",
    "verification ownership",
    "new-learning-intake.ps1",
    "invoke-weekly-harness-learning.ps1",
    "list_threads",
    "read_thread",
    "includeOutputs=false",
    "untrusted data",
    "proposal-only",
    "verification-skip",
    "source-sync",
    "audit-harness-components.ps1",
    "new-ablation-run.ps1",
    "web-source-resolver",
    "lane used",
    "sync direction",
    "suitable for commit and publish"
)) {
    if ($skill -notmatch [regex]::Escape($required)) {
        throw "Optimizer is missing required route or output term: $required"
    }
}
Add-Check -Name "routing-contract" -Detail "identity, lane, hook, context, agent, state, verification, learning, evolution, web, and output routes present"

foreach ($prohibited in @("鍙戠", "涓嶆", "鎻愪", "婧愮", [char]0xfffd)) {
    if ($skill.Contains([string]$prohibited)) {
        throw "Optimizer contains mojibake or replacement characters."
    }
}
Add-Check -Name "encoding" -Detail "UTF-8 text has no known mojibake markers"

$ui = Get-Content -LiteralPath (Join-Path $skillRoot "agents\openai.yaml") -Raw -Encoding UTF8
foreach ($field in @("display_name:", "short_description:", "default_prompt:")) {
    if ($ui -notmatch [regex]::Escape($field)) { throw "Optimizer UI metadata missing $field" }
}
Add-Check -Name "ui-metadata" -Detail "display name, summary, and default prompt present"

$validator = Join-Path $env:USERPROFILE ".codex\skills\.system\skill-creator\scripts\quick_validate.py"
$python = Get-Command python -ErrorAction SilentlyContinue
if ($python -and (Test-Path -LiteralPath $validator -PathType Leaf)) {
    $previousUtf8 = $env:PYTHONUTF8
    try {
        $env:PYTHONUTF8 = "1"
        & $python.Source $validator $skillRoot | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "quick_validate.py rejected the optimizer skill." }
    } finally {
        $env:PYTHONUTF8 = $previousUtf8
    }
    Add-Check -Name "skill-validator" -Detail "quick_validate.py passed"
}

[ordered]@{
    schema = "project-harness-optimizer-test-v1"
    status = "success"
    codex_home = $root
    checks = $checks.ToArray()
} | ConvertTo-Json -Depth 8 -Compress
