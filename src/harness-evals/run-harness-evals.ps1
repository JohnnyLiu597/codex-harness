param(
    [string]$CodexHome = "$env:USERPROFILE\.codex",
    [string[]]$EvalName = @(),
    [switch]$AllowFailures,
    [switch]$KeepFailedArtifacts
)

$ErrorActionPreference = "Stop"

$runStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$codexHomePath = (Resolve-Path -LiteralPath $CodexHome).Path
$runId = ((Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssfffZ")) + "-$PID-" + [guid]::NewGuid().ToString("N").Substring(0, 12)
$runRoot = Join-Path $codexHomePath "harness-evals\runs"
$runDir = Join-Path $runRoot $runId
$jsonPath = Join-Path $runDir "evals.json"
$summaryPath = Join-Path $runDir "summary.md"
$results = New-Object System.Collections.Generic.List[object]
$script:activeEvalTempRoots = New-Object System.Collections.Generic.List[string]
$script:retainedTempRoots = New-Object System.Collections.Generic.List[string]

New-Item -ItemType Directory -Force -Path $runDir | Out-Null

function New-EvalTempRoot {
    param([Parameter(Mandatory = $true)][string]$Prefix)

    $tempBase = [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $name = $Prefix + (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssfffZ") + "-$PID-" + [guid]::NewGuid().ToString("N").Substring(0, 10)
    $path = Join-Path $tempBase $name
    New-Item -ItemType Directory -Force -Path $path | Out-Null
    $resolved = (Resolve-Path -LiteralPath $path).Path
    $script:activeEvalTempRoots.Add($resolved) | Out-Null
    return $resolved
}

function Remove-EvalTempRoot {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    $tempBase = [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $resolved = [System.IO.Path]::GetFullPath($Path).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $prefix = $tempBase + [System.IO.Path]::DirectorySeparatorChar
    $leaf = Split-Path -Leaf $resolved
    if (-not $resolved.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) -or $leaf -notmatch '^codex-[A-Za-z0-9-]+-eval-') {
        throw "Refusing to clean a path outside the harness eval TEMP boundary."
    }
    foreach ($item in @(Get-ChildItem -LiteralPath $resolved -Force -Recurse -ErrorAction SilentlyContinue)) {
        try { $item.IsReadOnly = $false } catch { }
    }
    [System.IO.Directory]::Delete($resolved, $true)
}

function Get-EvalFailureClass {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)

    $message = [string]$ErrorRecord.Exception.Message
    if ($message -match '(?i)timeout|timed out') { return "timeout" }
    if ($message -match '(?i)not found|missing') { return "missing-dependency" }
    if ($ErrorRecord.Exception -is [System.Management.Automation.CommandNotFoundException]) { return "command-not-found" }
    return "assertion"
}

function Add-EvalResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Status,
        [string]$Detail = "",
        [string]$FailureClass = "none",
        [int]$DurationMs = 0,
        [int]$TempRootCount = 0,
        [int]$TempRootsCleaned = 0,
        [string[]]$TempRootsRetained = @()
    )
    $results.Add([pscustomobject]@{
        name = $Name
        status = $Status
        detail = $Detail
        failure_class = $FailureClass
        attempt = 1
        duration_ms = $DurationMs
        temp_root_count = $TempRootCount
        temp_roots_cleaned = $TempRootsCleaned
        temp_roots_retained = @($TempRootsRetained)
    }) | Out-Null
}

function Invoke-Eval {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Script
    )

    if ($EvalName.Count -gt 0 -and @($EvalName | Where-Object { $_ -ieq $Name }).Count -eq 0) { return }

    $script:activeEvalTempRoots = New-Object System.Collections.Generic.List[string]
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $status = "passed"
    $failureClass = "none"
    $detail = ""
    try {
        $detail = ((& $Script) | Out-String).Trim()
    } catch {
        $status = "failed"
        $failureClass = Get-EvalFailureClass -ErrorRecord $_
        $detail = $_.Exception.Message
    } finally {
        $stopwatch.Stop()
        $tempRoots = @($script:activeEvalTempRoots.ToArray())
        $cleaned = 0
        $retained = New-Object System.Collections.Generic.List[string]
        $cleanupFailures = 0

        foreach ($tempRoot in $tempRoots) {
            if ($status -eq "failed" -and $KeepFailedArtifacts) {
                $retained.Add($tempRoot) | Out-Null
                $script:retainedTempRoots.Add($tempRoot) | Out-Null
                continue
            }
            try {
                Remove-EvalTempRoot -Path $tempRoot
                $cleaned++
            } catch {
                $cleanupFailures++
                $retained.Add($tempRoot) | Out-Null
                $script:retainedTempRoots.Add($tempRoot) | Out-Null
            }
        }

        if ($cleanupFailures -gt 0) {
            $status = "failed"
            $failureClass = "cleanup"
            $detail = (($detail, "TEMP cleanup failed for $cleanupFailures root(s).") | Where-Object { $_ }) -join " "
        }

        Add-EvalResult -Name $Name -Status $status -Detail $detail -FailureClass $failureClass `
            -DurationMs ([int][Math]::Round($stopwatch.Elapsed.TotalMilliseconds)) -TempRootCount $tempRoots.Count `
            -TempRootsCleaned $cleaned -TempRootsRetained $retained.ToArray()
    }
}

Invoke-Eval -Name "global-config" -Script {
    $agents = Get-Content -LiteralPath (Join-Path $codexHomePath "AGENTS.md") -Raw
    foreach ($required in @(
        @{ Name = "reasoning budget"; Pattern = "Spend reasoning budget on the task" },
        @{ Name = "optional commentary"; Pattern = "Do not send optional commentary" },
        @{ Name = "meaningful state updates"; Pattern = "short,\s+factual,\s+and\s+tied\s+to\s+meaningful\s+state\s+changes" }
    )) {
        if ($agents -notmatch $required.Pattern) {
            throw "global AGENTS.md is missing quiet commentary guidance: $($required.Name)"
        }
    }
    "global guidance invariants verified without owning the global verifier"
}

Invoke-Eval -Name "optimizer-workflow-routing" -Script {
    $raw = & (Join-Path $codexHomePath "harness-evals\test-project-harness-optimizer.ps1") -CodexHome $codexHomePath
    $result = $raw | ConvertFrom-Json
    if ($result.status -ne "success") { throw "project-harness-optimizer self-test failed" }
    "project-harness-optimizer routes lanes, lifecycle, context, agents, state, verification, learning, evolution, web intake, and release closure"
}

Invoke-Eval -Name "weekly-harness-learning" -Script {
    $raw = & (Join-Path $codexHomePath "harness-evals\test-weekly-harness-learning.ps1") -CodexHome $codexHomePath
    $result = $raw | ConvertFrom-Json
    if ($result.status -ne "success") { throw "weekly harness learning self-test failed" }
    "weekly learning sanitized task evidence, deduplicated state, and enforced the automatic-change gate"
}

Invoke-Eval -Name "web-source-resolver" -Script {
    $skillPath = Join-Path $codexHomePath "skills\web-source-resolver\SKILL.md"
    $skill = Get-Content -LiteralPath $skillPath -Raw
    $globalAgents = Get-Content -LiteralPath (Join-Path $codexHomePath "AGENTS.md") -Raw
    foreach ($required in @(
        "across all projects",
        "public HTTP(S) URL",
        "resolve-web-source.ps1",
        "client-shell",
        "article-source-resolver",
        "PDF",
        "JSON",
        "Do not turn every URL into an article-reading task",
        "user intent, resource kind, and render state",
        "must not be used to bypass"
    )) {
        if ($skill -notmatch [regex]::Escape($required)) {
            throw "web-source-resolver is missing required global URL guidance: $required"
        }
    }
    foreach ($required in @(
        "Global Web Source Intake",
        "web-source-resolver",
        "In every project",
        "message containing only URLs defaults",
        "assume every URL is an article",
        "declared and detected content type"
    )) {
        if ($globalAgents -notmatch [regex]::Escape($required)) {
            throw "Global AGENTS.md is missing required web source routing: $required"
        }
    }
    & (Join-Path $codexHomePath "harness-evals\test-web-source-resolver.ps1") -CodexHome $codexHomePath | Out-Null
    "global web source resolver handled intent-aware HTML, structured data, documents, media, client shells, and safety gates"
}

Invoke-Eval -Name "article-source-resolver" -Script {
    $skillPath = Join-Path $codexHomePath "skills\article-source-resolver\SKILL.md"
    $skill = Get-Content -LiteralPath $skillPath -Raw
    foreach ($required in @(
        "A-full-page",
        "C-index-only",
        "D-blocked",
        "resolve-article-source.ps1",
        "must not be used to bypass",
        "user-exported HTML or PDF",
        "Do not use as the generic entry point for arbitrary URLs",
        "web-source-resolver",
        "JSON-LD Article"
    )) {
        if ($skill -notmatch [regex]::Escape($required)) {
            throw "article-source-resolver is missing required evidence guidance: $required"
        }
    }
    & (Join-Path $codexHomePath "harness-evals\test-article-source-resolver.ps1") -CodexHome $codexHomePath | Out-Null
    "article source resolver parsed classic, structured, generic main, and JSON-LD fixtures and classified blocked pages"
}

Invoke-Eval -Name "project-scaffold" -Script {
    $tmpRoot = New-EvalTempRoot -Prefix "codex-harness-eval-"
    & (Join-Path $codexHomePath "scripts\init-project-harness.ps1") -Root $tmpRoot -ProjectName "HarnessEval" -MajorChange -PlanName "eval" | Out-Null
    $expected = @(
        "AGENTS.md",
        "mission.md",
        "CONTEXT.md",
        "MEMORY.md",
        "harness.capabilities.json",
        "harness.components.json",
        "docs\project.md",
        "docs\architecture.md",
        "docs\code-map.md",
        "docs\features.json",
        "docs\commands.md",
        "docs\testing.md",
        "docs\smoke.md",
        "docs\loop.md",
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
        "docs\context-budget.md",
        "docs\job-state.md",
        "docs\component-evolution.md",
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
        "scripts\new-job-state.ps1",
        "scripts\new-learning-intake.ps1",
        "scripts\new-runtime-run.ps1",
        "scripts\invoke-verification-gate.ps1",
        "scripts\invoke-verification-envelope.ps1",
        "scripts\summarize-trace-evals.ps1",
        "scripts\new-tool-failure.ps1",
        "scripts\audit-skill-surface.ps1",
        "scripts\audit-context-budget.ps1",
        "scripts\audit-harness-components.ps1",
        "scripts\new-ablation-run.ps1",
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
        "artifacts\verification-envelopes",
        "artifacts\context-budget",
        "artifacts\component-audits",
        "artifacts\ablation-runs",
        "artifacts\job-states",
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
    $loop = Get-Content -LiteralPath (Join-Path $tmpRoot "docs\loop.md") -Raw
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
    foreach ($required in @("Layer Diagnosis", "L4 Admission", "maker-checker", "budget", "Stop Conditions", "Comprehension Debt")) {
        if ($loop -notmatch [regex]::Escape($required)) {
            throw "loop scaffold is missing required policy text: $required"
        }
    }
    "scaffold generated expected files plus risk-tiered verification and loop admission docs"
}

Invoke-Eval -Name "maturity-layer" -Script {
    $tmpRoot = New-EvalTempRoot -Prefix "codex-maturity-eval-"
    & (Join-Path $codexHomePath "scripts\init-project-harness.ps1") -Root $tmpRoot -ProjectName "MaturityEval" | Out-Null
    & (Join-Path $tmpRoot "scripts\check-features.ps1") | Out-Null
    & (Join-Path $tmpRoot "scripts\check-tool-evals.ps1") | Out-Null
    & (Join-Path $tmpRoot "scripts\check-architecture.ps1") | Out-Null
    & (Join-Path $tmpRoot "scripts\check-architecture.ps1") -ChangedOnly | Out-Null
    & (Join-Path $tmpRoot "scripts\init-agent-session.ps1") -Json | Out-Null
    & (Join-Path $tmpRoot "scripts\audit-project-harness.ps1") | Out-Null
    & (Join-Path $tmpRoot "scripts\new-session-summary.ps1") -Name "eval summary" -Objective "Verify session handoff records." -Completed @("created") -NextActions @("resume") -SetCurrent | Out-Null
    & (Join-Path $tmpRoot "scripts\new-agent-run.ps1") -Name "eval worker" -Role "worker" -Task "Verify worker output contract." -Outputs @("record") -Checks @("json") | Out-Null
    & (Join-Path $tmpRoot "scripts\new-job-state.ps1") -Name "eval job" -WorkType manual -State running -Summary "Verify resumable native job records." | Out-Null
    & (Join-Path $tmpRoot "scripts\new-learning-intake.ps1") -Name "eval learning" -Summary "Verify learning intake." -ProposedDestination "eval" -Evidence @("record") | Out-Null
    & (Join-Path $tmpRoot "scripts\new-runtime-run.ps1") -Name "eval runtime" -Status "completed" -Summary "Verify runtime evidence records." -Checks @("runtime") -Evidence @("record") | Out-Null
    & (Join-Path $tmpRoot "scripts\invoke-verification-gate.ps1") -Mode DocsOnly -ContinueOnError | Out-Null
    & (Join-Path $tmpRoot "scripts\run-codex-trace-evals.ps1") -DryRun | Out-Null
    & (Join-Path $tmpRoot "scripts\summarize-trace-evals.ps1") -Last 5 | Out-Null
    & (Join-Path $tmpRoot "scripts\new-tool-failure.ps1") -Tool "eval-tool" -FailureType "other" -Summary "Verify tool failure records." -Recovery "recorded" | Out-Null
    & (Join-Path $tmpRoot "scripts\audit-skill-surface.ps1") -ProjectRoot $tmpRoot | Out-Null
    & (Join-Path $tmpRoot "scripts\audit-context-budget.ps1") -ProjectRoot $tmpRoot -CodexHome $codexHomePath | Out-Null
    & (Join-Path $tmpRoot "scripts\audit-harness-components.ps1") -ProjectRoot $tmpRoot | Out-Null
    & (Join-Path $tmpRoot "scripts\new-ablation-run.ps1") -Name "eval ablation" -ComponentId "project-operating-docs" -Hypothesis "A bounded comparison record preserves evidence without changing component state." -MaxCases 1 -MaxMinutes 1 | Out-Null
    & (Join-Path $tmpRoot "scripts\invoke-verification-envelope.ps1") -ProjectRoot $tmpRoot -Name "eval envelope" -Command "Get-Content -LiteralPath '.\mission.md' | Out-Null" -SourcePaths @("mission.md") -TestPaths @("scripts\verify-harness.ps1") -ProtectedPaths @("mission.md") -TimeoutSeconds 10 | Out-Null
    & (Join-Path $tmpRoot "scripts\check-all.ps1") -TraceEvals -Smoke | Out-Null
    "maturity layer scripts ran on generated scaffold"
}

Invoke-Eval -Name "job-state-adapter" -Script {
    $tmpRoot = New-EvalTempRoot -Prefix "codex-job-state-eval-"
    & (Join-Path $codexHomePath "scripts\init-project-harness.ps1") -Root $tmpRoot -ProjectName "JobStateEval" | Out-Null
    $script = Join-Path $tmpRoot "scripts\new-job-state.ps1"
    $count = 0
    foreach ($workType in @("goal", "subagent", "worktree", "scheduled", "event-driven", "manual")) {
        foreach ($state in @("queued", "running", "checking", "waiting_approval", "passed", "blocked", "stopped")) {
            $args = @{
                Name = "$workType $state"
                WorkType = $workType
                State = $state
                JobId = "$workType-$state"
                Summary = "mapping eval"
            }
            if ($state -eq "passed") { $args.Artifacts = @("verification:evaluated") }
            if ($state -in @("blocked", "stopped")) { $args.StopReason = "bounded eval stop" }
            $raw = & $script @args
            $json = $raw | ConvertFrom-Json
            if ($json.status -eq "failed" -or $json.state -ne $state) {
                throw "job-state mapping failed for $workType/$state"
            }
            $count++
        }
    }

    & $script -Name "resume history" -WorkType manual -State queued -JobId "resume-history" -Summary "queued" | Out-Null
    & $script -Name "resume history" -WorkType manual -State running -JobId "resume-history" -Attempt 2 -Summary "running" | Out-Null
    $historyPath = Join-Path $tmpRoot "artifacts\job-states\resume-history\history.jsonl"
    if (@(Get-Content -LiteralPath $historyPath).Count -ne 2) {
        throw "job-state history did not append both attempts"
    }
    "new-job-state mapped $count native work/state combinations and preserved append-only history"
}

Invoke-Eval -Name "context-and-component-evolution" -Script {
    $tmpRoot = New-EvalTempRoot -Prefix "codex-component-eval-"
    & (Join-Path $codexHomePath "scripts\init-project-harness.ps1") -Root $tmpRoot -ProjectName "ComponentEval" | Out-Null

    $context = (& (Join-Path $tmpRoot "scripts\audit-context-budget.ps1") -ProjectRoot $tmpRoot -CodexHome $codexHomePath) | ConvertFrom-Json
    if (-not $context.read_only -or $context.status -eq "failed") {
        throw "context budget audit did not remain read-only"
    }

    $components = (& (Join-Path $tmpRoot "scripts\audit-harness-components.ps1") -ProjectRoot $tmpRoot) | ConvertFrom-Json
    if (-not $components.read_only -or $components.status -ne "passed" -or $components.component_count -lt 8) {
        throw "component registry audit did not pass with all component types"
    }

    $ablationRaw = & (Join-Path $tmpRoot "scripts\new-ablation-run.ps1") -Name "bounded eval" -ComponentId "project-operating-docs" -Hypothesis "A record can compare a component without mutating its state." -MaxCases 1 -MaxMinutes 1
    $ablation = $ablationRaw | ConvertFrom-Json
    $record = Get-Content -LiteralPath $ablation.artifacts[0] -Raw | ConvertFrom-Json
    if ($record.automatic_component_changes -or $record.component_state_changed) {
        throw "ablation record changed component state"
    }
    "context budget, component registry, and bounded ablation controls passed"
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
    $tmpRoot = New-EvalTempRoot -Prefix "codex-tool-failure-eval-"
    $tmpRoot = (Resolve-Path -LiteralPath $tmpRoot).Path
    & (Join-Path $codexHomePath "scripts\init-project-harness.ps1") -Root $tmpRoot -ProjectName "ToolFailureEval" | Out-Null
    $toolFailureScript = Join-Path $tmpRoot "scripts\new-tool-failure.ps1"
    $processOutput = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $toolFailureScript `
        -ProjectRoot $tmpRoot -Tool "fixture-tool" -FailureType "timeout" -Summary "eval tool failure" `
        -Operation "open page" -Error "timeout" -Recovery "retry with snapshot" -Evidence "log" 2>&1)
    $processExit = $LASTEXITCODE
    if ($processExit -ne 0) { throw "new-tool-failure failed in an independent PowerShell process" }
    $json = ($processOutput -join "`n") | ConvertFrom-Json
    foreach ($artifact in $json.artifacts) {
        if (-not (Test-Path -LiteralPath $artifact)) { throw "tool failure artifact missing: $artifact" }
    }
    "new-tool-failure created tool failure evidence from an independent PowerShell process"
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
    $raw = & (Join-Path $codexHomePath "harness-evals\test-verification-gate.ps1") -CodexHome $codexHomePath
    $result = $raw | ConvertFrom-Json
    if ($result.status -ne "success") { throw "verification gate self-test failed" }
    "verification gate preserved real process exits, bounded artifacts, and explicit mode semantics"
}

Invoke-Eval -Name "runtime-evidence-record" -Script {
    $tmpRoot = New-EvalTempRoot -Prefix "codex-runtime-evidence-eval-"
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
    $tmpRoot = New-EvalTempRoot -Prefix "codex-coordination-eval-"
    & (Join-Path $codexHomePath "scripts\init-project-harness.ps1") -Root $tmpRoot -ProjectName "CoordinationEval" | Out-Null

    $sessionRaw = & (Join-Path $tmpRoot "scripts\new-session-summary.ps1") -Name "eval handoff" -Status "handoff" -Objective "Preserve context." -Completed @("one") -Decisions @("two") -NextActions @("three") -Files @("CONTEXT.md") -Checks @("verify") -SetCurrent
    $session = $sessionRaw | ConvertFrom-Json
    foreach ($artifact in $session.artifacts) {
        if (-not (Test-Path -LiteralPath $artifact)) { throw "session artifact missing: $artifact" }
    }
    if (-not (Test-Path -LiteralPath $session.current)) { throw "session current pointer missing" }

    $inputMarker = "agent-input-must-not-persist-7f64015e"
    $agentRaw = & (Join-Path $tmpRoot "scripts\new-agent-run.ps1") -Name "eval agent" -Role "worker" -Task "Return bounded evidence." -Inputs @($inputMarker) -Outputs @("summary") -Risks @("none") -Ownership @("docs") -CheckerIdentity "independent-checker" -TimeBudgetMinutes 5
    $agent = $agentRaw | ConvertFrom-Json
    foreach ($artifact in $agent.artifacts) {
        if (-not (Test-Path -LiteralPath $artifact)) { throw "agent artifact missing: $artifact" }
    }
    $agentArtifacts = ($agent.artifacts | ForEach-Object { Get-Content -LiteralPath $_ -Raw }) -join "`n"
    if ($agentArtifacts -match [regex]::Escape($inputMarker)) {
        throw "agent run persisted raw inputs without -PersistInputs"
    }
    $agentRecord = Get-Content -LiteralPath $agent.artifacts[0] -Raw | ConvertFrom-Json
    if ($agentRecord.inputs_persisted -or $agentRecord.input_count -ne 1 -or @($agentRecord.input_hashes).Count -ne 1) {
        throw "agent run did not preserve input-count and hash evidence"
    }

    $learningRaw = & (Join-Path $tmpRoot "scripts\new-learning-intake.ps1") -Name "eval intake" -Source "eval" -Summary "Repeated miss should become docs or eval." -FailureMode "missed handoff" -Frequency "repeated" -ProposedDestination "trace-eval" -Evidence @("case")
    $learning = $learningRaw | ConvertFrom-Json
    foreach ($artifact in $learning.artifacts) {
        if (-not (Test-Path -LiteralPath $artifact)) { throw "learning artifact missing: $artifact" }
    }
    if ($learning.route -ne "eval" -or $learning.automatic_destination_changes) {
        throw "learning intake did not resolve the route without automatic changes"
    }

    "coordination record scripts created handoff, worker, and learning artifacts"
}

Invoke-Eval -Name "harness-change-record" -Script {
    $tmpRoot = New-EvalTempRoot -Prefix "codex-harness-change-eval-"
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
    $tmpRoot = New-EvalTempRoot -Prefix "codex-trace-intake-eval-"
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
    $tmpRoot = New-EvalTempRoot -Prefix "codex-review-eval-"
    & (Join-Path $codexHomePath "scripts\init-project-harness.ps1") -Root $tmpRoot -ProjectName "ReviewEval" | Out-Null
    $script = Join-Path $tmpRoot "scripts\new-review.ps1"
    & $script -Name "eval-review" -Status "completed" -Summary "eval" -Checks @("check") -Evidence @("evidence") -Maker "maker" -Checker "checker" -VerifiedCommit "0123456789abcdef" | Out-Null
    $run = Get-ChildItem -LiteralPath (Join-Path $tmpRoot "artifacts\reviews") -Directory | Select-Object -First 1
    if (-not $run -or -not (Test-Path -LiteralPath (Join-Path $run.FullName "review.json"))) {
        throw "review record was not created"
    }
    $review = Get-Content -LiteralPath (Join-Path $run.FullName "review.json") -Raw | ConvertFrom-Json
    if (-not $review.maker_checker_separated -or $review.maker -eq $review.checker) {
        throw "review record did not preserve maker/checker separation"
    }
    "new-review created independent maker/checker evidence"
}

Invoke-Eval -Name "goal-record" -Script {
    $tmpRoot = New-EvalTempRoot -Prefix "codex-goal-eval-"
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
    $tmpRoot = New-EvalTempRoot -Prefix "codex-smoke-eval-"
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
    $tmpRoot = New-EvalTempRoot -Prefix "codex-safe-remove-eval-"
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
    $tmpRoot = New-EvalTempRoot -Prefix "codex-docs-sync-eval-"
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

Invoke-Eval -Name "workflow-core-hooks" -Script {
    $raw = & (Join-Path $codexHomePath "scripts\test-codex-workflow-core.ps1") -CodexHome $codexHomePath
    $result = $raw | ConvertFrom-Json
    if ($result.status -ne "success") { throw "workflow core hook self-test failed" }
    "lifecycle hooks passed safety, privacy, valid-output, and bounded verification-loop checks"
}

Invoke-Eval -Name "verification-envelope" -Script {
    $raw = & (Join-Path $codexHomePath "harness-evals\test-verification-envelope.ps1") -CodexHome $codexHomePath
    $result = $raw | ConvertFrom-Json
    if ($result.status -ne "success") { throw "verification envelope self-test failed" }
    "verification envelope passed required evidence, before/after hash, stale-input, timeout, cleanup, and policy/evidence separation checks"
}

Invoke-Eval -Name "trace-evals-v3" -Script {
    $raw = & (Join-Path $codexHomePath "harness-evals\test-trace-evals-v3.ps1") -CodexHome $codexHomePath
    $result = $raw | ConvertFrom-Json
    if ($result.status -ne "success") { throw "trace eval v3 self-test failed" }
    "trace eval v3 passed final-message grading, privacy, attempts/duration/failure classes, timeout cleanup, status propagation, TEMP cleanup, and unique run checks"
}

$failed = @($results | Where-Object { $_.status -eq "failed" })
$runStatus = if ($failed.Count -gt 0) { "failed" } else { "passed" }
$topStatus = if ($runStatus -eq "failed") { "failed" } else { "success" }
$runStopwatch.Stop()
$durationMs = [int][Math]::Round($runStopwatch.Elapsed.TotalMilliseconds)
$retainedTempRoots = @($script:retainedTempRoots.ToArray())

$record = [pscustomobject]@{
    schema = "codex-harness-evals-v3"
    run_id = $runId
    status = $topStatus
    run_status = $runStatus
    created_at = (Get-Date).ToString("o")
    duration_ms = $durationMs
    codex_home = $codexHomePath
    selected_evals = @($EvalName)
    keep_failed_artifacts = [bool]$KeepFailedArtifacts
    retained_temp_roots = $retainedTempRoots
    failure_classes = @($failed | Select-Object -ExpandProperty failure_class -Unique)
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

- Run ID: $runId
- Status: $runStatus
- Created: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
- Duration ms: $durationMs
- Codex home: $codexHomePath
- Retained TEMP roots: $($retainedTempRoots.Count)

## Results

$resultLines

## Artifacts

- evals.json
"@

Set-Content -LiteralPath $summaryPath -Value $md -Encoding UTF8

if ($failed.Count -gt 0 -and -not $AllowFailures) {
    throw "Harness evals failed: $($failed.name -join ', ')"
}

[ordered]@{
    status = $topStatus
    run_status = $runStatus
    summary = if ($runStatus -eq "passed") { "Codex harness evals passed." } else { "Codex harness evals completed with failures." }
    run_id = $runId
    duration_ms = $durationMs
    failure_classes = $record.failure_classes
    retained_temp_roots = $retainedTempRoots
    results = $results.ToArray()
    artifacts = @($jsonPath, $summaryPath)
} | ConvertTo-Json -Depth 10 -Compress
