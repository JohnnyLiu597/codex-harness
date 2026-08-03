param(
    [string]$CodexHome = "$env:USERPROFILE\.codex"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $CodexHome).Path
$skillRoot = Join-Path $root "skills\project-harness-optimizer"
$skillPath = Join-Path $skillRoot "SKILL.md"
$checks = New-Object System.Collections.Generic.List[object]

function Add-Check {
    param([string]$Name, [string]$Detail)
    $checks.Add([pscustomobject]@{ name = $Name; status = "passed"; detail = $Detail }) | Out-Null
}

if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) {
    throw "project-harness-optimizer SKILL.md missing: $skillPath"
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
    "references\project-scaffold.md",
    "agents\openai.yaml"
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $skillRoot $reference) -PathType Leaf)) {
        throw "Optimizer resource missing: $reference"
    }
}
Add-Check -Name "resources" -Detail "maintenance, workflow, scaffold, and UI metadata present"

$workflowReference = Get-Content -LiteralPath (Join-Path $skillRoot "references\workflow-state-and-evidence.md") -Raw -Encoding UTF8
foreach ($required in @("standalone TOML", "name", "description", "developer_instructions", "active Codex model")) {
    if ($workflowReference -notmatch [regex]::Escape($required)) {
        throw "Optimizer workflow reference is missing portable custom-agent guidance: $required"
    }
}
Add-Check -Name "custom-agent-contract" -Detail "standalone schema and model inheritance guidance present"

foreach ($required in @(
    "Runtime Hotfix",
    "Source Release",
    "Audit Only",
    "hooks.json",
    "audit-context-budget.ps1",
    "new-agent-run.ps1",
    "new-job-state.ps1",
    "invoke-verification-envelope.ps1",
    "invoke-verification-gate.ps1",
    "new-learning-intake.ps1",
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
Add-Check -Name "routing-contract" -Detail "lane, hook, context, agent, state, verification, learning, evolution, web, and output routes present"

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
