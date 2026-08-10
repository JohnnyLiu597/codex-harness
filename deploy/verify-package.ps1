param(
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
} else {
    $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
}

$srcRoot = Join-Path $ProjectRoot "src"
$checks = New-Object System.Collections.Generic.List[object]

function Add-Check {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Detail
    )
    $checks.Add([pscustomobject]@{ name = $Name; status = $Status; detail = $Detail }) | Out-Null
}

function Test-RequiredPath {
    param([string]$RelativePath)

    $path = Join-Path $ProjectRoot $RelativePath
    if (Test-Path -LiteralPath $path) {
        Add-Check -Name "required:$RelativePath" -Status "passed" -Detail "present"
    } else {
        Add-Check -Name "required:$RelativePath" -Status "failed" -Detail "missing"
    }
}

foreach ($path in @(
    "AGENTS.md",
    "mission.md",
    "CONTEXT.md",
    "MEMORY.md",
    "README.md",
    ".gitignore",
    "docs\project.md",
    "docs\architecture.md",
    "docs\commands.md",
    "docs\testing.md",
    "docs\release.md",
    "docs\security.md",
    "deploy\sync-from-runtime.ps1",
    "deploy\sync-to-runtime.ps1",
    "deploy\test-sync-boundaries.ps1",
    "deploy\test-transactional-release.ps1",
    "deploy\verify-release.ps1",
    "deploy\verify-package.ps1"
)) {
    Test-RequiredPath -RelativePath $path
}

foreach ($path in @(
    "src\AGENTS.md",
    "src\CODEX.md",
    "src\harness.capabilities.json",
    "src\harness.components.json",
    "src\hooks.json",
    "src\automations\harness\automation.toml.template",
    "src\agents\explorer.toml",
    "src\agents\reviewer.toml",
    "src\agents\docs-researcher.toml",
    "src\agents\tester.toml",
    "src\agents\harness-auditor.toml",
    "src\docs",
    "src\rules",
    "src\scripts\verify-global-harness.ps1",
    "src\scripts\codex-hook.ps1",
    "src\scripts\codex-hook-router.ps1",
    "src\scripts\invoke-verification-gate.ps1",
    "src\scripts\invoke-verification-envelope.ps1",
    "src\scripts\audit-context-budget.ps1",
    "src\scripts\audit-harness-components.ps1",
    "src\scripts\new-job-state.ps1",
    "src\scripts\new-ablation-run.ps1",
    "src\scripts\invoke-weekly-harness-learning.ps1",
    "src\scripts\harness-health.ps1",
    "src\scripts\audit-skill-surface.ps1",
    "src\templates\project-harness\harness.capabilities.json",
    "src\templates\project-harness\harness.components.json",
    "src\templates\project-harness\context-budget.md",
    "src\templates\project-harness\job-state.md",
    "src\templates\project-harness\component-evolution.md",
    "src\templates\project-harness\loop.md",
    "src\harness-evals\run-harness-evals.ps1",
    "src\harness-evals\test-trace-evals-v3.ps1",
    "src\harness-evals\test-verification-gate.ps1",
    "src\harness-evals\test-verification-envelope.ps1",
    "src\harness-evals\test-project-harness-optimizer.ps1",
    "src\harness-evals\test-weekly-harness-learning.ps1",
    "src\harness-evals\test-article-source-resolver.ps1",
    "src\skills\article-source-resolver\SKILL.md",
    "src\skills\article-source-resolver\scripts\resolve-article-source.ps1",
    "src\skills\article-source-resolver\scripts\resolve_article_source.py",
    "src\skills\project-harness-optimizer\SKILL.md",
    "src\skills\harness-orchestrator\SKILL.md",
    "src\skills\harness-orchestrator\references\workflow-graph-contract.md",
    "src\docs\weekly-learning.md"
)) {
    $full = Join-Path $ProjectRoot $path
    if (Test-Path -LiteralPath $full) {
        Add-Check -Name "payload:$path" -Status "passed" -Detail "present"
    } else {
        Add-Check -Name "payload:$path" -Status "failed" -Detail "missing"
    }
}

if (Test-Path -LiteralPath $srcRoot) {
    $files = @(Get-ChildItem -LiteralPath $srcRoot -Recurse -Force -File -ErrorAction SilentlyContinue)
    $forbidden = @($files | Where-Object {
        $_.Name -in @("auth.json", "config.toml") -or
        $_.Name -like "*.sqlite*" -or
        $_.Name -like "*.pyc" -or
        $_.Name -like "*.pyo" -or
        $_.Name -eq ".codex-private" -or
        $_.Name -match '(?i)\.bak(?:[-.].*)?$|\.backup(?:[-.].*)?$|~$' -or
        $_.Name -eq ".sync-manifest.json" -or
        $_.FullName -match '\\(plugins?|caches?|sessions?|archived_sessions|logs?|hook-logs|browser(?:[ ._-]?state)?|computer-use|process_manager|harness-health|harness-changes|harness-learning|skills\.archived|agents\.archived|backups?|backup-[^\\]+|\.sandbox(?:-bin|-secrets)?|\.tmp|tmp)\\' -or
        $_.FullName -match '\\scripts\\archived\\' -or
        $_.FullName -match '\\__pycache__\\' -or
        $_.FullName -match '\\harness-evals\\runs\\' -or
        $_.FullName -match '\\harness-evals\\trace-evals\\(runs|summaries)\\'
    })
    if ($forbidden.Count -eq 0) {
        Add-Check -Name "forbidden-runtime-files" -Status "passed" -Detail "none found"
    } else {
        Add-Check -Name "forbidden-runtime-files" -Status "failed" -Detail (($forbidden | Select-Object -First 20 -ExpandProperty FullName) -join "; ")
    }
}

$automationRoot = Join-Path $srcRoot "automations"
$automationTemplatePath = Join-Path $automationRoot "harness\automation.toml.template"
if (Test-Path -LiteralPath $automationRoot -PathType Container) {
    $automationRootFull = (Get-Item -LiteralPath $automationRoot).FullName.TrimEnd('\') + '\'
    $unexpectedAutomationFiles = @(Get-ChildItem -LiteralPath $automationRoot -Recurse -Force -File | Where-Object {
        $relative = $_.FullName.Substring($automationRootFull.Length).Replace('/', '\')
        $relative -ne 'harness\automation.toml.template'
    })
    if ($unexpectedAutomationFiles.Count -eq 0) {
        Add-Check -Name "automation-source-allowlist" -Status "passed" -Detail "only the public automation template is present"
    } else {
        Add-Check -Name "automation-source-allowlist" -Status "failed" -Detail (($unexpectedAutomationFiles | Select-Object -First 20 -ExpandProperty FullName) -join "; ")
    }
}

if (Test-Path -LiteralPath $automationTemplatePath) {
    $template = Get-Content -LiteralPath $automationTemplatePath -Raw
    $missingPlaceholders = @("__CODEX_HOME_TOML_CONTENT__", "__PROJECT_ROOT_TOML_STRING__", "__NOW_MS__") | Where-Object {
        $template -notmatch [regex]::Escape($_)
    }
    if ($missingPlaceholders.Count -eq 0) {
        Add-Check -Name "automation-template-placeholders" -Status "passed" -Detail "all placeholders present"
    } else {
        Add-Check -Name "automation-template-placeholders" -Status "failed" -Detail ($missingPlaceholders -join ", ")
    }

    if ($template -match 'C:\\Users\\' -or $template -match '(?i)Johnny' -or $template -match '(?i)(experimental_bearer_token|bearer_token|api[_-]?key|token)\s*=') {
        Add-Check -Name "automation-template-public-readiness" -Status "failed" -Detail "template contains personal, machine-local, or secret-like content"
    } else {
        Add-Check -Name "automation-template-public-readiness" -Status "passed" -Detail "no machine-local path or secret-like field"
    }

    if ($template -match '(?m)^\s*(model|model_reasoning_effort|reasoning_effort)\s*=') {
        Add-Check -Name "automation-template-adaptive-capability" -Status "failed" -Detail "template pins model or reasoning effort"
    } elseif ($template -notmatch '(?m)^\s*execution_environment\s*=\s*"worktree"\s*$') {
        Add-Check -Name "automation-template-adaptive-capability" -Status "failed" -Detail "template does not use worktree isolation"
    } else {
        Add-Check -Name "automation-template-adaptive-capability" -Status "passed" -Detail "model and reasoning use app defaults under worktree isolation"
    }

    $missingLearningTerms = @(
        "Your first operation must be",
        "invoke-weekly-harness-learning.ps1",
        "temporary_input_prefix",
        "Do not run any other shell command before the final exact Complete command",
        "list_threads",
        "read_thread",
        "includeOutputs=false",
        "turnLimit=10",
        "untrusted data",
        "official OpenAI sources",
        "Edit zero maintainable harness or source files",
        "completion script deletes it after parsing",
        "Do not alter config, auth, hooks, agents, rules, scripts, skills, templates, manifests, deployment code, repositories, or business projects",
        "Do not delete, commit, push, release, publish, or sync"
    ) | Where-Object { $template -notmatch [regex]::Escape($_) }
    if ($missingLearningTerms.Count -eq 0) {
        Add-Check -Name "automation-template-weekly-learning" -Status "passed" -Detail "bounded learning, research, privacy, and publish boundaries present"
    } else {
        Add-Check -Name "automation-template-weekly-learning" -Status "failed" -Detail ($missingLearningTerms -join ", ")
    }
}

$weeklyLearningScriptPath = Join-Path $srcRoot "scripts\invoke-weekly-harness-learning.ps1"
if (Test-Path -LiteralPath $weeklyLearningScriptPath -PathType Leaf) {
    $weeklyLearningScript = Get-Content -LiteralPath $weeklyLearningScriptPath -Raw -Encoding UTF8
    $legacyControls = @('ApprovedMaintenance', 'SyncSource', 'SourceProjectRoot', 'SkipVerification') | Where-Object {
        $weeklyLearningScript -match ('(?m)^\s*\[(?:switch|string)\]\$' + [regex]::Escape($_) + '\b')
    }
    if ($legacyControls.Count -eq 0) {
        Add-Check -Name "weekly-learning-proposal-only-interface" -Status "passed" -Detail "no maintenance, verification-skip, or source-sync parameters"
    } else {
        Add-Check -Name "weekly-learning-proposal-only-interface" -Status "failed" -Detail ($legacyControls -join ', ')
    }
}

foreach ($jsonRelative in @("harness.capabilities.json", "harness.components.json", "hooks.json", "templates\project-harness\harness.capabilities.json", "templates\project-harness\harness.components.json", "templates\project-harness\features.json")) {
    $jsonPath = Join-Path $srcRoot $jsonRelative
    if (-not (Test-Path -LiteralPath $jsonPath -PathType Leaf)) { continue }
    try {
        Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json | Out-Null
        Add-Check -Name "json:$jsonRelative" -Status "passed" -Detail "valid JSON"
    } catch {
        Add-Check -Name "json:$jsonRelative" -Status "failed" -Detail $_.Exception.Message
    }
}

$hooksPath = Join-Path $srcRoot "hooks.json"
if (Test-Path -LiteralPath $hooksPath -PathType Leaf) {
    $hooksRaw = Get-Content -LiteralPath $hooksPath -Raw -Encoding UTF8
    $hooks = $hooksRaw | ConvertFrom-Json
    $requiredHookEvents = @("SessionStart", "PreToolUse", "PermissionRequest", "PostToolUse", "PreCompact", "PostCompact", "UserPromptSubmit", "SubagentStart", "SubagentStop", "Stop")
    $missingHookEvents = @($requiredHookEvents | Where-Object { $hooks.hooks.PSObject.Properties.Name -notcontains $_ })
    if ($missingHookEvents.Count -eq 0) {
        Add-Check -Name "hooks-lifecycle-surface" -Status "passed" -Detail "required Desktop-reviewable lifecycle events present"
    } else {
        Add-Check -Name "hooks-lifecycle-surface" -Status "failed" -Detail ("missing: " + ($missingHookEvents -join ", "))
    }
    $sessionEndStatus = if ($hooks.hooks.PSObject.Properties.Name -contains "SessionEnd") { "configured" } else { "optional-omitted" }
    Add-Check -Name "hooks-optional-session-end" -Status "passed" -Detail $sessionEndStatus
    if ($hooksRaw -match 'C:\\Users\\' -or $hooksRaw -match 'auth\.json|config\.toml|bearer_token|api[_-]?key') {
        Add-Check -Name "hooks-public-readiness" -Status "failed" -Detail "hooks contain a machine-local path or secret-adjacent field"
    } else {
        Add-Check -Name "hooks-public-readiness" -Status "passed" -Detail "portable commands and no secret-adjacent fields"
    }
}

$agentRoot = Join-Path $srcRoot "agents"
if (Test-Path -LiteralPath $agentRoot -PathType Container) {
    $agentFiles = @(Get-ChildItem -LiteralPath $agentRoot -File -Filter "*.toml" | Sort-Object Name)
    $agentNames = New-Object System.Collections.Generic.HashSet[string]
    $agentIssues = New-Object System.Collections.Generic.List[string]
    foreach ($agentFile in $agentFiles) {
        $agentConfig = Get-Content -LiteralPath $agentFile.FullName -Raw -Encoding UTF8
        $nameMatch = [regex]::Match($agentConfig, '(?m)^\s*name\s*=\s*"([^"]+)"\s*$')
        $descriptionMatch = [regex]::Match($agentConfig, '(?m)^\s*description\s*=\s*"([^"]+)"\s*$')
        if (-not $nameMatch.Success -or -not $descriptionMatch.Success -or $agentConfig -notmatch '(?m)^\s*developer_instructions\s*=') {
            $agentIssues.Add("$($agentFile.Name): missing name, description, or developer_instructions") | Out-Null
            continue
        }
        if ($agentConfig -match '(?m)^\s*(model|model_reasoning_effort|reasoning_effort)\s*=') {
            $agentIssues.Add("$($agentFile.Name): reusable role pins model or reasoning effort") | Out-Null
        }
        $agentName = $nameMatch.Groups[1].Value
        $expectedName = [System.IO.Path]::GetFileNameWithoutExtension($agentFile.Name).Replace("-", "_")
        if ($agentName -ne $expectedName) {
            $agentIssues.Add("$($agentFile.Name): name '$agentName' should be '$expectedName'") | Out-Null
        }
        if (-not $agentNames.Add($agentName)) {
            $agentIssues.Add("$($agentFile.Name): duplicate name '$agentName'") | Out-Null
        }
    }
    if ($agentFiles.Count -gt 0 -and $agentIssues.Count -eq 0) {
        Add-Check -Name "custom-agent-schema" -Status "passed" -Detail "$($agentFiles.Count) standalone agent files are portable"
    } else {
        Add-Check -Name "custom-agent-schema" -Status "failed" -Detail (($agentIssues.ToArray()) -join "; ")
    }
}

$globalVerifierPath = Join-Path $ProjectRoot 'src\scripts\verify-global-harness.ps1'
$evalRunnerPath = Join-Path $ProjectRoot 'src\harness-evals\run-harness-evals.ps1'
if ((Test-Path -LiteralPath $globalVerifierPath -PathType Leaf) -and
    (Test-Path -LiteralPath $evalRunnerPath -PathType Leaf)) {
    $globalVerifierContent = Get-Content -LiteralPath $globalVerifierPath -Raw -Encoding UTF8
    $evalRunnerContent = Get-Content -LiteralPath $evalRunnerPath -Raw -Encoding UTF8
    if ($globalVerifierContent -match '(?m)^\s*&\s+.*(?:test-[A-Za-z0-9_-]+\.ps1|run-harness-evals\.ps1)') {
        Add-Check -Name 'verification-ownership' -Status 'failed' -Detail 'global verifier executes deterministic behavior tests'
    } elseif (@(
        'test-codex-workflow-core.ps1',
        'test-verification-gate.ps1',
        'test-verification-envelope.ps1',
        'test-trace-evals-v3.ps1',
        'test-weekly-harness-learning.ps1'
    ) | Where-Object { $evalRunnerContent -notmatch [regex]::Escape($_) }) {
        Add-Check -Name 'verification-ownership' -Status 'failed' -Detail 'deterministic eval runner is missing one or more workflow-core regression owners'
    } else {
        Add-Check -Name 'verification-ownership' -Status 'passed' -Detail 'global verifier owns static/runtime health and eval runner owns deterministic behavior cases'
    }
}

foreach ($relative in @(
    'src\harness-evals\run-trace-evals.ps1',
    'src\templates\project-harness\scripts\run-codex-trace-evals.ps1',
    'src\scripts\init-project-harness.ps1',
    'src\scripts\verify-global-harness.ps1'
)) {
    $path = Join-Path $ProjectRoot $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    if ($content -match [regex]::Escape("OpenAI\Codex\bin\codex.exe") -and
        $content -match 'Resolve-CodexCommand' -and
        $content -match 'Get-Command\s+codex\s+-All' -and
        $content -match '--version') {
        Add-Check -Name ("codex-cli-resolution:" + $relative) -Status "passed" -Detail "executable candidate is probed before use"
    } else {
        Add-Check -Name ("codex-cli-resolution:" + $relative) -Status "failed" -Detail "missing executable fallback or --version probe"
    }
}

$psScripts = @()
foreach ($dir in @("deploy", "src")) {
    $full = Join-Path $ProjectRoot $dir
    if (Test-Path -LiteralPath $full) {
        $psScripts += @(Get-ChildItem -LiteralPath $full -Recurse -File -Filter "*.ps1" -ErrorAction SilentlyContinue)
    }
}

$parseErrors = New-Object System.Collections.Generic.List[string]
foreach ($script in $psScripts) {
    $errors = $null
    [System.Management.Automation.PSParser]::Tokenize((Get-Content -LiteralPath $script.FullName -Raw), [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        $parseErrors.Add("$($script.FullName): $($errors[0].Message)") | Out-Null
    }
}
if ($parseErrors.Count -eq 0) {
    Add-Check -Name "powershell-parse" -Status "passed" -Detail "$($psScripts.Count) scripts parsed"
} else {
    Add-Check -Name "powershell-parse" -Status "failed" -Detail ($parseErrors -join "; ")
}

$resolverPython = Join-Path $srcRoot "skills\article-source-resolver\scripts\resolve_article_source.py"
$python = Get-Command python -ErrorAction SilentlyContinue
if ($python -and (Test-Path -LiteralPath $resolverPython -PathType Leaf)) {
    $astCheck = "import ast,pathlib; ast.parse(pathlib.Path(r'" + $resolverPython.Replace("'", "''") + "').read_text(encoding='utf-8'))"
    & $python.Source -c $astCheck
    if ($LASTEXITCODE -eq 0) {
        Add-Check -Name "article-resolver-python" -Status "passed" -Detail "Python syntax parsed"
    } else {
        Add-Check -Name "article-resolver-python" -Status "failed" -Detail "Python syntax validation failed"
    }
} else {
    Add-Check -Name "article-resolver-python" -Status "passed" -Detail "Python unavailable; runtime wrapper reports the dependency explicitly"
}

$skillRoot = Join-Path $srcRoot "skills"
if (Test-Path -LiteralPath $skillRoot) {
    $skillDirs = @(Get-ChildItem -LiteralPath $skillRoot -Directory -Force)
    $missingSkillMd = @($skillDirs | Where-Object { -not (Test-Path -LiteralPath (Join-Path $_.FullName "SKILL.md")) })
    $invalidSkillMd = New-Object System.Collections.Generic.List[string]
    foreach ($skillDir in $skillDirs) {
        $skillPath = Join-Path $skillDir.FullName "SKILL.md"
        if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) { continue }
        $bytes = [System.IO.File]::ReadAllBytes($skillPath)
        if ($bytes.Length -lt 3 -or $bytes[0] -ne 0x2D -or $bytes[1] -ne 0x2D -or $bytes[2] -ne 0x2D) {
            $invalidSkillMd.Add("$($skillDir.Name): SKILL.md must start with --- in UTF-8 without BOM") | Out-Null
            continue
        }
        $skillText = Get-Content -LiteralPath $skillPath -Raw -Encoding UTF8
        $frontmatter = [regex]::Match($skillText, '\A---\r?\n(?<body>[\s\S]*?)\r?\n---(?:\r?\n|$)')
        if (-not $frontmatter.Success) {
            $invalidSkillMd.Add("$($skillDir.Name): malformed YAML frontmatter") | Out-Null
            continue
        }
        $metadata = $frontmatter.Groups["body"].Value
        $name = [regex]::Match($metadata, '(?m)^name:\s*["'']?(?<value>[^\r\n"'']+)')
        $description = [regex]::Match($metadata, '(?m)^description:\s*(?<value>\S.*)$')
        if (-not $name.Success -or $name.Groups["value"].Value.Trim() -ne $skillDir.Name -or -not $description.Success) {
            $invalidSkillMd.Add("$($skillDir.Name): name/description metadata is missing or inconsistent") | Out-Null
        }
    }
    if ($missingSkillMd.Count -eq 0 -and $invalidSkillMd.Count -eq 0) {
        Add-Check -Name "skill-frontmatter-surface" -Status "passed" -Detail "$($skillDirs.Count) skill directories have loadable SKILL.md frontmatter"
    } else {
        $details = @($missingSkillMd | ForEach-Object { "$($_.Name): missing SKILL.md" }) + @($invalidSkillMd)
        Add-Check -Name "skill-frontmatter-surface" -Status "failed" -Detail ($details -join "; ")
    }
}

$status = if (@($checks | Where-Object { $_.status -eq "failed" }).Count -gt 0) { "failed" } else { "passed" }
$report = [ordered]@{
    schema = "codex-harness-package-check-v1"
    status = $status
    created_at = (Get-Date).ToString("o")
    project_root = $ProjectRoot
    checks = $checks.ToArray()
}

$reportDir = Join-Path $ProjectRoot "artifacts\checks"
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$reportPath = Join-Path $reportDir ((Get-Date -Format "yyyyMMdd-HHmmss") + "-package-check.json")
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8

if ($status -eq "failed") {
    $report | ConvertTo-Json -Depth 8 -Compress
    throw "Package verification failed. See $reportPath"
}

[ordered]@{
    status = "success"
    summary = "Codex harness package verified."
    report = $reportPath
} | ConvertTo-Json -Depth 8 -Compress
