param(
    [string]$CodexHome = "$env:USERPROFILE\.codex"
)

$ErrorActionPreference = "Stop"

$codexHomePath = (Resolve-Path -LiteralPath $CodexHome).Path
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runRoot = Join-Path $codexHomePath "harness-evals\runs"
$runDir = Join-Path $runRoot $stamp
$jsonPath = Join-Path $runDir "evals.json"
$summaryPath = Join-Path $runDir "summary.md"
$results = New-Object System.Collections.Generic.List[object]

New-Item -ItemType Directory -Force -Path $runDir | Out-Null

function Add-EvalResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Status,
        [string]$Detail = ""
    )
    $results.Add([pscustomobject]@{
        name = $Name
        status = $Status
        detail = $Detail
    }) | Out-Null
}

function Invoke-Eval {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Script
    )

    try {
        $detail = & $Script
        Add-EvalResult -Name $Name -Status "passed" -Detail ([string]$detail)
    } catch {
        Add-EvalResult -Name $Name -Status "failed" -Detail $_.Exception.Message
    }
}

Invoke-Eval -Name "global-config" -Script {
    & (Join-Path $codexHomePath "scripts\verify-global-harness.ps1") -CodexHome $codexHomePath | Out-Null
    "global config and script syntax verified"
}

Invoke-Eval -Name "optimizer-workflow-routing" -Script {
    $skillPath = Join-Path $codexHomePath "skills\project-harness-optimizer\SKILL.md"
    $skill = Get-Content -LiteralPath $skillPath -Raw
    foreach ($required in @(
        "Workflow Core Routing Table",
        "Route Selection Discipline",
        "Closed-Loop Evidence Contract",
        "Workflow Recipes",
        "Hook Upgrade Checklist",
        "Agent Upgrade Checklist",
        "Testing Loop Upgrade Checklist",
        "Completion Gates For Workflow Core Work",
        "Workflow Core Mode",
        "codex-hook-router.ps1",
        "detect-project-test-surface.ps1",
        "invoke-codex-workflow.ps1",
        "test-codex-workflow-core.ps1",
        "reproduce -> fix -> rerun",
        "new-tool-failure.ps1",
        "new-agent-run.ps1",
        "verify-release.ps1",
        "lowest sufficient release gate",
        "idempotent setup/cleanup",
        "allowed `"not found`" or HTTP 404",
        "bounded timeouts",
        "partial evidence on timeout",
        "harness-auditor",
        "regression-miner"
    )) {
        if ($skill -notmatch [regex]::Escape($required)) {
            throw "project-harness-optimizer is missing required workflow routing text: $required"
        }
    }
    "project-harness-optimizer actively routes workflow core hooks, agents, workflows, tests, and completion gates"
}

Invoke-Eval -Name "project-scaffold" -Script {
    $tmpRoot = Join-Path $env:TEMP ("codex-harness-eval-" + (Get-Date -Format "yyyyMMddHHmmssfff"))
    New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
    & (Join-Path $codexHomePath "scripts\init-project-harness.ps1") -Root $tmpRoot -ProjectName "HarnessEval" -MajorChange -PlanName "eval" | Out-Null
    $expected = @(
        "AGENTS.md",
        "mission.md",
        "CONTEXT.md",
        "MEMORY.md",
        "harness.capabilities.json",
        "docs\project.md",
        "docs\architecture.md",
        "docs\code-map.md",
        "docs\features.json",
        "docs\commands.md",
        "docs\testing.md",
        "docs\smoke.md",
        "docs\observability.md",
        "docs\quality.md",
        "docs\reliability.md",
        "docs\security.md",
        "docs\tech-debt.md",
        "docs\auth.md",
        "docs\profiles.md",
        "docs\retention.md",
        "docs\context.md",
        "docs\tool-surface.md",
        "docs\runtime.md",
        "docs\verification-gate.md",
        "docs\trace-evals.md",
        "docs\tool-failures.md",
        "docs\skill-surface.md",
        "evals\README.md",
        "evals\prompts.csv",
        "evals\tool-evals\README.md",
        "evals\tool-evals\cases\tool-selection-smoke.json",
        "evals\tool-evals\cases\safety-smoke.json",
        "artifacts\templates\major-task-plan.md",
        "artifacts\templates\goal-plan.md",
        "artifacts\templates\harness-change.md",
        "artifacts\templates\agent-task.md",
        "scripts\audit-worktree.ps1",
        "scripts\audit-project-harness.ps1",
        "scripts\check-all.ps1",
        "scripts\check-architecture.ps1",
        "scripts\check-features.ps1",
        "scripts\check-project-docs.ps1",
        "scripts\check-tool-evals.ps1",
        "scripts\grade-codex-trace-evals.ps1",
        "scripts\init-agent-session.ps1",
        "scripts\new-goal.ps1",
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
        "scripts\new-review.ps1",
        "scripts\new-run.ps1",
        "scripts\new-smoke-run.ps1",
        "scripts\run-codex-trace-evals.ps1",
        "scripts\smoke-canvas.ps1",
        "scripts\smoke-persistence.ps1",
        "scripts\smoke-routing.ps1",
        "scripts\safe-remove.ps1",
        "scripts\update-project-state.ps1",
        "scripts\verify-harness.ps1",
        ".codex\rules\default.rules",
        "artifacts\plan_eval.md"
    )
    $missing = @()
    foreach ($rel in $expected) {
        if (-not (Test-Path -LiteralPath (Join-Path $tmpRoot $rel))) {
            $missing += $rel
        }
    }
    if ($missing.Count -gt 0) {
        throw "missing scaffold files: $($missing -join ', ')"
    }
    $testing = Get-Content -LiteralPath (Join-Path $tmpRoot "docs\testing.md") -Raw
    $smoke = Get-Content -LiteralPath (Join-Path $tmpRoot "docs\smoke.md") -Raw
    if ($testing -notmatch 'L0' -or $testing -notmatch 'L5' -or $testing -notmatch 'lowest verification layer') {
        throw "testing scaffold does not describe the L0-L5 verification ladder"
    }
    if ($testing -notmatch 'idempotent setup and cleanup' -or $testing -notmatch 'HTTP 404' -or $testing -notmatch 'bounded timeout') {
        throw "testing scaffold does not describe reusable smoke idempotency and timeout evidence"
    }
    if ($smoke -notmatch 'Do not run every available smoke' -or $smoke -notmatch 'blocked verification') {
        throw "smoke scaffold does not describe risk-selected smoke and blocked verification"
    }
    if ($smoke -notmatch 'Reusable Smoke Scripts' -or $smoke -notmatch 'not\s+found' -or $smoke -notmatch 'known-valid fixtures' -or $smoke -notmatch 'bounded timeout') {
        throw "smoke scaffold does not describe reusable L4 smoke closure rules"
    }
    "scaffold generated expected files and risk-tiered verification docs"
}

Invoke-Eval -Name "maturity-layer" -Script {
    $tmpRoot = Join-Path $env:TEMP ("codex-maturity-eval-" + (Get-Date -Format "yyyyMMddHHmmssfff"))
    New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
    & (Join-Path $codexHomePath "scripts\init-project-harness.ps1") -Root $tmpRoot -ProjectName "MaturityEval" | Out-Null
    & (Join-Path $tmpRoot "scripts\check-features.ps1") | Out-Null
    & (Join-Path $tmpRoot "scripts\check-tool-evals.ps1") | Out-Null
    & (Join-Path $tmpRoot "scripts\check-architecture.ps1") | Out-Null
    & (Join-Path $tmpRoot "scripts\check-architecture.ps1") -ChangedOnly | Out-Null
    & (Join-Path $tmpRoot "scripts\init-agent-session.ps1") -Json | Out-Null
    & (Join-Path $tmpRoot "scripts\audit-project-harness.ps1") | Out-Null
    & (Join-Path $tmpRoot "scripts\new-session-summary.ps1") -Name "eval summary" -Objective "Verify session handoff records." -Completed @("created") -NextActions @("resume") -SetCurrent | Out-Null
    & (Join-Path $tmpRoot "scripts\new-agent-run.ps1") -Name "eval worker" -Role "worker" -Task "Verify worker output contract." -Outputs @("record") -Checks @("json") | Out-Null
    & (Join-Path $tmpRoot "scripts\new-learning-intake.ps1") -Name "eval learning" -Summary "Verify learning intake." -ProposedDestination "eval" -Evidence @("record") | Out-Null
    & (Join-Path $tmpRoot "scripts\new-runtime-run.ps1") -Name "eval runtime" -Status "completed" -Summary "Verify runtime evidence records." -Checks @("runtime") -Evidence @("record") | Out-Null
    & (Join-Path $tmpRoot "scripts\invoke-verification-gate.ps1") -Mode DocsOnly -ContinueOnError | Out-Null
    & (Join-Path $tmpRoot "scripts\run-codex-trace-evals.ps1") -DryRun | Out-Null
    & (Join-Path $tmpRoot "scripts\summarize-trace-evals.ps1") -Last 5 | Out-Null
    & (Join-Path $tmpRoot "scripts\new-tool-failure.ps1") -Tool "eval-tool" -FailureType "other" -Summary "Verify tool failure records." -Recovery "recorded" | Out-Null
    & (Join-Path $tmpRoot "scripts\audit-skill-surface.ps1") -ProjectRoot $tmpRoot | Out-Null
    & (Join-Path $tmpRoot "scripts\check-all.ps1") -TraceEvals -Smoke | Out-Null
    "maturity layer scripts ran on generated scaffold"
}

Invoke-Eval -Name "trace-summary" -Script {
    $traceRaw = & (Join-Path $codexHomePath "harness-evals\run-trace-evals.ps1") -CodexHome $codexHomePath -DryRun
    $trace = $traceRaw | ConvertFrom-Json
    foreach ($artifact in $trace.artifacts) {
        if (-not (Test-Path -LiteralPath $artifact)) {
            throw "trace dry-run artifact missing: $artifact"
        }
    }
    $summaryRaw = & (Join-Path $codexHomePath "scripts\summarize-trace-evals.ps1") -CodexHome $codexHomePath -Last 5
    $summary = $summaryRaw | ConvertFrom-Json
    foreach ($artifact in $summary.artifacts) {
        if (-not (Test-Path -LiteralPath $artifact)) {
            throw "trace summary artifact missing: $artifact"
        }
    }
    "summarize-trace-evals created trace trend artifacts"
}

Invoke-Eval -Name "tool-failure-record" -Script {
    $tmpRoot = Join-Path $env:TEMP ("codex-tool-failure-eval-" + (Get-Date -Format "yyyyMMddHHmmssfff"))
    New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
    $tmpRoot = (Resolve-Path -LiteralPath $tmpRoot).Path
    & (Join-Path $codexHomePath "scripts\init-project-harness.ps1") -Root $tmpRoot -ProjectName "ToolFailureEval" | Out-Null
    $raw = & (Join-Path $tmpRoot "scripts\new-tool-failure.ps1") -Tool "playwright" -FailureType "timeout" -Summary "eval tool failure" -Operation "open page" -Error "timeout" -Recovery "retry with snapshot" -Evidence @("log")
    $json = $raw | ConvertFrom-Json
    foreach ($artifact in $json.artifacts) {
        if (-not (Test-Path -LiteralPath $artifact)) { throw "tool failure artifact missing: $artifact" }
    }
    "new-tool-failure created tool failure evidence"
}

Invoke-Eval -Name "skill-surface-stocktake" -Script {
    $raw = & (Join-Path $codexHomePath "scripts\audit-skill-surface.ps1") -CodexHome $codexHomePath
    $json = $raw | ConvertFrom-Json
    if ($json.status -eq "failed") {
        throw "skill surface stocktake failed"
    }
    foreach ($artifact in $json.artifacts) {
        if (-not (Test-Path -LiteralPath $artifact)) { throw "skill stocktake artifact missing: $artifact" }
    }
    "audit-skill-surface created read-only stocktake"
}

Invoke-Eval -Name "verification-gate" -Script {
    $tmpRoot = Join-Path $env:TEMP ("codex-verification-gate-eval-" + (Get-Date -Format "yyyyMMddHHmmssfff"))
    New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
    $tmpRoot = (Resolve-Path -LiteralPath $tmpRoot).Path
    & (Join-Path $codexHomePath "scripts\init-project-harness.ps1") -Root $tmpRoot -ProjectName "VerificationGateEval" | Out-Null

    foreach ($mode in @("DocsOnly", "HarnessOnly")) {
        $raw = & (Join-Path $tmpRoot "scripts\invoke-verification-gate.ps1") -Mode $mode -ContinueOnError
        $json = $raw | ConvertFrom-Json
        if ($json.status -eq "failed") {
            throw "verification gate failed in $mode mode"
        }
        foreach ($artifact in $json.artifacts) {
            if (-not (Test-Path -LiteralPath $artifact)) {
                throw "verification gate artifact missing: $artifact"
            }
            if ($artifact -notmatch '\\artifacts\\verification-gates\\') {
                throw "verification gate artifact has unexpected path: $artifact"
            }
        }
        if (-not (Test-Path -LiteralPath (Join-Path $tmpRoot "artifacts\verification-gates"))) {
            throw "verification gate directory missing under project root"
        }
    }

    "invoke-verification-gate produced project-local gate artifacts"
}

Invoke-Eval -Name "runtime-evidence-record" -Script {
    $tmpRoot = Join-Path $env:TEMP ("codex-runtime-evidence-eval-" + (Get-Date -Format "yyyyMMddHHmmssfff"))
    New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
    & (Join-Path $codexHomePath "scripts\init-project-harness.ps1") -Root $tmpRoot -ProjectName "RuntimeEvidenceEval" | Out-Null

    $raw = & (Join-Path $tmpRoot "scripts\new-runtime-run.ps1") -Name "eval runtime feature proof" -Status "completed" -Summary "Runtime evidence can link back to features." -FeatureIds @("harness-001") -Commands @("verify") -Checks @("runtime check") -Evidence @("runtime observation") -UpdateFeatureEvidence
    $json = $raw | ConvertFrom-Json
    foreach ($artifact in $json.artifacts) {
        if (-not (Test-Path -LiteralPath $artifact)) { throw "runtime artifact missing: $artifact" }
    }
    if ("harness-001" -notin @($json.linked_feature_ids)) {
        throw "runtime run did not report linked feature id"
    }

    $features = Get-Content -LiteralPath (Join-Path $tmpRoot "docs\features.json") -Raw | ConvertFrom-Json
    $feature = @($features.features | Where-Object { $_.id -eq "harness-001" })[0]
    if (-not $feature.last_checked) {
        throw "runtime evidence did not update last_checked"
    }
    if (-not (@($feature.evidence) | Where-Object { $_ -match '^runtime-run:' })) {
        throw "runtime evidence entry was not appended"
    }
    & (Join-Path $tmpRoot "scripts\check-features.ps1") | Out-Null
    "new-runtime-run created runtime evidence and linked it to features.json"
}

Invoke-Eval -Name "coordination-records" -Script {
    $tmpRoot = Join-Path $env:TEMP ("codex-coordination-eval-" + (Get-Date -Format "yyyyMMddHHmmssfff"))
    New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
    & (Join-Path $codexHomePath "scripts\init-project-harness.ps1") -Root $tmpRoot -ProjectName "CoordinationEval" | Out-Null

    $sessionRaw = & (Join-Path $tmpRoot "scripts\new-session-summary.ps1") -Name "eval handoff" -Status "handoff" -Objective "Preserve context." -Completed @("one") -Decisions @("two") -NextActions @("three") -Files @("CONTEXT.md") -Checks @("verify") -SetCurrent
    $session = $sessionRaw | ConvertFrom-Json
    foreach ($artifact in $session.artifacts) {
        if (-not (Test-Path -LiteralPath $artifact)) { throw "session artifact missing: $artifact" }
    }
    if (-not (Test-Path -LiteralPath $session.current)) { throw "session current pointer missing" }

    $agentRaw = & (Join-Path $tmpRoot "scripts\new-agent-run.ps1") -Name "eval agent" -Role "worker" -Task "Return bounded evidence." -Inputs @("task") -Outputs @("summary") -Risks @("none")
    $agent = $agentRaw | ConvertFrom-Json
    foreach ($artifact in $agent.artifacts) {
        if (-not (Test-Path -LiteralPath $artifact)) { throw "agent artifact missing: $artifact" }
    }

    $learningRaw = & (Join-Path $tmpRoot "scripts\new-learning-intake.ps1") -Name "eval intake" -Source "eval" -Summary "Repeated miss should become docs or eval." -FailureMode "missed handoff" -Frequency "repeated" -ProposedDestination "trace-eval" -Evidence @("case")
    $learning = $learningRaw | ConvertFrom-Json
    foreach ($artifact in $learning.artifacts) {
        if (-not (Test-Path -LiteralPath $artifact)) { throw "learning artifact missing: $artifact" }
    }

    "coordination record scripts created handoff, worker, and learning artifacts"
}

Invoke-Eval -Name "harness-change-record" -Script {
    $tmpRoot = Join-Path $env:TEMP ("codex-harness-change-eval-" + (Get-Date -Format "yyyyMMddHHmmssfff"))
    New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
    & (Join-Path $codexHomePath "scripts\init-project-harness.ps1") -Root $tmpRoot -ProjectName "HarnessChangeEval" | Out-Null
    $script = Join-Path $tmpRoot "scripts\new-harness-change.ps1"
    & $script -Name "eval harness change" -Layer "eval" -Status "completed" -Summary "eval" -Files @("scripts\check-tool-evals.ps1") -Checks @("scripts\check-tool-evals.ps1") | Out-Null
    $run = Get-ChildItem -LiteralPath (Join-Path $tmpRoot "artifacts\harness-changes") -Directory | Select-Object -First 1
    if (-not $run -or -not (Test-Path -LiteralPath (Join-Path $run.FullName "change.json"))) {
        throw "harness change record was not created"
    }
    "new-harness-change created change evidence"
}

Invoke-Eval -Name "trace-eval-intake" -Script {
    $tmpRoot = Join-Path $env:TEMP ("codex-trace-intake-eval-" + (Get-Date -Format "yyyyMMddHHmmssfff"))
    New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
    & (Join-Path $codexHomePath "scripts\init-project-harness.ps1") -Root $tmpRoot -ProjectName "TraceIntakeEval" | Out-Null
    $script = Join-Path $tmpRoot "scripts\new-trace-eval.ps1"
    $raw = & $script -Name "eval repeated failure" -Prompt "A repeated harness failure should become a regression eval." -Expected "Creates a durable eval case." -MustInclude @("trace", "eval", "evidence") -MustNotInclude @("secret") -Lane "evals"
    $json = $raw | ConvertFrom-Json
    if (-not (Test-Path -LiteralPath $json.prompt_file)) {
        throw "prompt file missing after trace eval intake"
    }
    if (-not (Test-Path -LiteralPath $json.case_file)) {
        throw "case file missing after trace eval intake"
    }
    $cases = @(Import-Csv -LiteralPath $json.prompt_file | Where-Object { $_.id -eq $json.id })
    if ($cases.Count -ne 1) {
        throw "trace eval CSV row was not created"
    }
    "new-trace-eval created prompt row and case evidence"
}

Invoke-Eval -Name "review-record" -Script {
    $tmpRoot = Join-Path $env:TEMP ("codex-review-eval-" + (Get-Date -Format "yyyyMMddHHmmssfff"))
    New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
    & (Join-Path $codexHomePath "scripts\init-project-harness.ps1") -Root $tmpRoot -ProjectName "ReviewEval" | Out-Null
    $script = Join-Path $tmpRoot "scripts\new-review.ps1"
    & $script -Name "eval-review" -Status "completed" -Summary "eval" -Checks @("check") -Evidence @("evidence") | Out-Null
    $run = Get-ChildItem -LiteralPath (Join-Path $tmpRoot "artifacts\reviews") -Directory | Select-Object -First 1
    if (-not $run -or -not (Test-Path -LiteralPath (Join-Path $run.FullName "review.json"))) {
        throw "review record was not created"
    }
    "new-review created review evidence"
}

Invoke-Eval -Name "goal-record" -Script {
    $tmpRoot = Join-Path $env:TEMP ("codex-goal-eval-" + (Get-Date -Format "yyyyMMddHHmmssfff"))
    New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
    & (Join-Path $codexHomePath "scripts\init-project-harness.ps1") -Root $tmpRoot -ProjectName "GoalEval" | Out-Null
    $script = Join-Path $tmpRoot "scripts\new-goal.ps1"
    & $script -Name "eval-goal" -Objective "Keep the generated harness goal layer verifiable." -SuccessCriteria @("goal exists") -FeatureIds @("harness-001") -SetCurrent | Out-Null
    $run = Get-ChildItem -LiteralPath (Join-Path $tmpRoot "artifacts\goals") -Directory | Select-Object -First 1
    if (-not $run -or -not (Test-Path -LiteralPath (Join-Path $run.FullName "goal.json"))) {
        throw "goal record was not created"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $tmpRoot "artifacts\goals\current.md"))) {
        throw "current goal pointer was not created"
    }
    "new-goal created durable goal evidence"
}

Invoke-Eval -Name "generated-smoke-record" -Script {
    $tmpRoot = Join-Path $env:TEMP ("codex-smoke-eval-" + (Get-Date -Format "yyyyMMddHHmmssfff"))
    New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
    & (Join-Path $codexHomePath "scripts\init-project-harness.ps1") -Root $tmpRoot -ProjectName "SmokeEval" | Out-Null
    $script = Join-Path $tmpRoot "scripts\new-smoke-run.ps1"
    & $script -Name "eval-smoke" -Status "completed" -Summary "eval" -Checks @("check") -Evidence @("evidence") | Out-Null
    $run = Get-ChildItem -LiteralPath (Join-Path $tmpRoot "artifacts\smoke-runs") -Directory | Select-Object -First 1
    if (-not $run -or -not (Test-Path -LiteralPath (Join-Path $run.FullName "smoke.json"))) {
        throw "smoke record was not created"
    }
    "new-smoke-run created smoke evidence"
}

Invoke-Eval -Name "safe-remove" -Script {
    $tmpRoot = Join-Path $env:TEMP ("codex-safe-remove-eval-" + (Get-Date -Format "yyyyMMddHHmmssfff"))
    New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
    $file = Join-Path $tmpRoot "remove-me.txt"
    Set-Content -LiteralPath $file -Value "safe remove eval" -Encoding UTF8
    & (Join-Path $codexHomePath "scripts\safe-remove.ps1") $file -TrashRoot (Join-Path $tmpRoot ".codex-trash") | Out-Null
    if (Test-Path -LiteralPath $file) {
        throw "source file still exists after safe remove"
    }
    $trashFile = Get-ChildItem -LiteralPath (Join-Path $tmpRoot ".codex-trash") -Recurse -File | Select-Object -First 1
    if (-not $trashFile) {
        throw "file was not moved into trash"
    }
    "safe-remove moved file into trash staging"
}

Invoke-Eval -Name "docs-sync" -Script {
    $tmpRoot = Join-Path $env:TEMP ("codex-docs-sync-eval-" + (Get-Date -Format "yyyyMMddHHmmssfff"))
    New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
    & (Join-Path $codexHomePath "scripts\init-project-harness.ps1") -Root $tmpRoot -ProjectName "DocsSyncEval" | Out-Null
    git -C $tmpRoot init | Out-Null
    git -C $tmpRoot config user.email "codex@example.local" | Out-Null
    git -C $tmpRoot config user.name "Codex Eval" | Out-Null
    git -C $tmpRoot add -- . | Out-Null
    git -C $tmpRoot commit -m "initial scaffold" | Out-Null
    $raw = & (Join-Path $codexHomePath "scripts\check-project-docs.ps1") -ProjectRoot $tmpRoot
    $json = $raw | ConvertFrom-Json
    if ($json.status -notin @("passed", "warning")) {
        throw "unexpected docs sync status: $($json.status)"
    }
    "check-project-docs produced docs sync report"
}

Invoke-Eval -Name "hook-privacy" -Script {
    $hookScript = Join-Path $codexHomePath "scripts\codex-stop-log.ps1"
    $source = Get-Content -LiteralPath $hookScript -Raw
    if ($source -match '(?m)^\s*raw\s*=') {
        throw "Stop hook still records raw payload"
    }
    if ($source -match '(?m)^\s*payload\s*=') {
        throw "Stop hook still stores full parsed payload"
    }
    '{"summary":"harness eval stop hook"}' | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $hookScript | Out-Null
    $latest = Get-Content -LiteralPath (Join-Path $codexHomePath "hook-logs\latest-stop.txt") -Raw
    if ($latest -notmatch "harness eval stop hook") {
        throw "Stop hook did not write latest-stop.txt"
    }
    "Stop hook writes summary without raw payload fields"
}

Invoke-Eval -Name "trace-eval-dryrun" -Script {
    $traceRaw = & (Join-Path $codexHomePath "harness-evals\run-trace-evals.ps1") -CodexHome $codexHomePath -DryRun
    $trace = $traceRaw | ConvertFrom-Json
    if (-not $trace.dry_run) {
        throw "trace eval dry run did not report dry_run=true"
    }
    foreach ($artifact in $trace.artifacts) {
        if (-not (Test-Path -LiteralPath $artifact)) {
            throw "trace eval artifact missing: $artifact"
        }
    }
    "run-trace-evals.ps1 produced dry-run trace artifacts"
}

$failed = @($results | Where-Object { $_.status -eq "failed" })
$status = if ($failed.Count -gt 0) { "failed" } else { "passed" }

$record = [pscustomobject]@{
    schema = "codex-harness-evals-v1"
    status = $status
    created_at = (Get-Date).ToString("o")
    codex_home = $codexHomePath
    results = $results.ToArray()
}

$record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$resultLines = if ($results.Count -gt 0) {
    ($results | ForEach-Object { "- $($_.status): $($_.name) $($_.detail)" }) -join "`r`n"
} else {
    "- No evals recorded."
}

$md = @"
# Codex Harness Evals

- Status: $status
- Created: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
- Codex home: $codexHomePath

## Results

$resultLines

## Artifacts

- evals.json
"@

Set-Content -LiteralPath $summaryPath -Value $md -Encoding UTF8

if ($failed.Count -gt 0) {
    throw "Harness evals failed: $($failed.name -join ', ')"
}

[ordered]@{
    status = "success"
    summary = "Codex harness evals passed."
    artifacts = @($jsonPath, $summaryPath)
} | ConvertTo-Json -Depth 5 -Compress
