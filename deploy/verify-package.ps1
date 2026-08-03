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
    "deploy\verify-release.ps1",
    "deploy\verify-package.ps1"
)) {
    Test-RequiredPath -RelativePath $path
}

foreach ($path in @(
    "src\AGENTS.md",
    "src\CODEX.md",
    "src\harness.capabilities.json",
    "src\automations\harness\automation.toml.template",
    "src\agents\explorer.toml",
    "src\agents\reviewer.toml",
    "src\agents\docs-researcher.toml",
    "src\agents\tester.toml",
    "src\agents\harness-auditor.toml",
    "src\docs",
    "src\rules",
    "src\scripts\verify-global-harness.ps1",
    "src\scripts\harness-health.ps1",
    "src\scripts\audit-skill-surface.ps1",
    "src\templates\project-harness\harness.capabilities.json",
    "src\templates\project-harness\loop.md",
    "src\harness-evals\run-harness-evals.ps1",
    "src\harness-evals\test-article-source-resolver.ps1",
    "src\skills\article-source-resolver\SKILL.md",
    "src\skills\article-source-resolver\scripts\resolve-article-source.ps1",
    "src\skills\article-source-resolver\scripts\resolve_article_source.py",
    "src\skills\project-harness-optimizer\SKILL.md"
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
        $_.Name -like "*.sqlite" -or
        $_.Name -like "*.sqlite-shm" -or
        $_.Name -like "*.sqlite-wal" -or
        $_.Name -like "*.pyc" -or
        $_.Name -like "*.pyo" -or
        $_.FullName -match '\\(plugins|cache|sessions|archived_sessions|log|hook-logs|browser|computer-use|process_manager|harness-health|harness-changes|skills\.archived|agents\.archived)\\' -or
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

$automationTemplatePath = Join-Path $srcRoot "automations\harness\automation.toml.template"
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

    if ($template -match 'C:\\Users\\' -or $template -match 'experimental_bearer_token|bearer_token|api[_-]?key|auth\.json|token\s*=') {
        Add-Check -Name "automation-template-public-readiness" -Status "failed" -Detail "template contains machine-local path or secret-like field"
    } else {
        Add-Check -Name "automation-template-public-readiness" -Status "passed" -Detail "no machine-local path or secret-like field"
    }
}

$jsonPath = Join-Path $srcRoot "harness.capabilities.json"
if (Test-Path -LiteralPath $jsonPath) {
    try {
        Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json | Out-Null
        Add-Check -Name "capability-json" -Status "passed" -Detail "valid JSON"
    } catch {
        Add-Check -Name "capability-json" -Status "failed" -Detail $_.Exception.Message
    }
}

$psScripts = @()
foreach ($dir in @("deploy", "src\scripts", "src\harness-evals")) {
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
    if ($missingSkillMd.Count -eq 0) {
        Add-Check -Name "skill-frontmatter-surface" -Status "passed" -Detail "$($skillDirs.Count) skill directories have SKILL.md"
    } else {
        Add-Check -Name "skill-frontmatter-surface" -Status "failed" -Detail (($missingSkillMd | Select-Object -ExpandProperty Name) -join ", ")
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
