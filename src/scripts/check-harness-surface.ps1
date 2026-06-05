param(
    [string]$CodexHome = "$env:USERPROFILE\.codex",
    [int]$MaxActiveSkills = 50
)

$ErrorActionPreference = "Stop"

$codexHomePath = (Resolve-Path -LiteralPath $CodexHome).Path
$configPath = Join-Path $codexHomePath "config.toml"
$capabilityPath = Join-Path $codexHomePath "harness.capabilities.json"
$skillsRoot = Join-Path $codexHomePath "skills"
$agentsRoot = Join-Path $codexHomePath "agents"

$checks = New-Object System.Collections.Generic.List[object]

function Add-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Status,
        [string]$Detail = ""
    )
    $checks.Add([pscustomobject]@{
        name = $Name
        status = $Status
        detail = $Detail
    }) | Out-Null
}

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

$activeSkillDirs = @()
if (Test-Path -LiteralPath $skillsRoot) {
    $activeSkillDirs = @(Get-ChildItem -LiteralPath $skillsRoot -Directory -Force)
}

if ($activeSkillDirs.Count -gt $MaxActiveSkills) {
    Add-Check -Name "active-skill-count" -Status "warning" -Detail "$($activeSkillDirs.Count) active skill directories; target is <= $MaxActiveSkills."
} else {
    Add-Check -Name "active-skill-count" -Status "passed" -Detail "$($activeSkillDirs.Count) active skill directories."
}

$containerDirs = @(".system", "codex-primary-runtime")
$missingSkillMd = @()
foreach ($dir in $activeSkillDirs) {
    if ($containerDirs -contains $dir.Name) { continue }
    if (-not (Test-Path -LiteralPath (Join-Path $dir.FullName "SKILL.md"))) {
        $missingSkillMd += $dir.Name
    }
}
if ($missingSkillMd.Count -gt 0) {
    Add-Check -Name "skill-frontmatter" -Status "warning" -Detail "Missing SKILL.md: $($missingSkillMd -join ', ')"
} else {
    Add-Check -Name "skill-frontmatter" -Status "passed" -Detail "All non-container active skills have SKILL.md."
}

if (Test-Path -LiteralPath $configPath) {
    $config = Get-Content -LiteralPath $configPath -Raw

    if ($config -match '(?m)^\s*experimental_bearer_token\s*=') {
        Add-Check -Name "provider-token-location" -Status "warning" -Detail "config.toml contains experimental_bearer_token; prefer env/auth indirection for portable harnesses."
    } else {
        Add-Check -Name "provider-token-location" -Status "passed" -Detail "No experimental_bearer_token field found in config.toml."
    }

    $mcpNames = Get-McpServerNames -Config $config
    $mcpSubsections = Get-McpSubsections -Config $config
    Add-Check -Name "mcp-surface" -Status "info" -Detail "servers: $($mcpNames -join ', ')"
    if ($mcpSubsections.Count -gt 0) {
        Add-Check -Name "mcp-subsections" -Status "info" -Detail "subsections: $($mcpSubsections -join ', ')"
    }

    $agentNames = @([regex]::Matches($config, '(?m)^\[agents\.([^\]]+)\]') |
        ForEach-Object { $_.Groups[1].Value } |
        Sort-Object -Unique)
    if ($agentNames.Count -gt 0) {
        Add-Check -Name "agent-surface" -Status "info" -Detail "agents: $($agentNames -join ', ')"
    }

    $missingAgentConfigs = New-Object System.Collections.Generic.List[string]
    foreach ($match in [regex]::Matches($config, '(?ms)^\[agents\.([^\]]+)\](.*?)(?=^\[|\z)')) {
        $name = $match.Groups[1].Value
        $section = $match.Groups[2].Value
        $configMatch = [regex]::Match($section, 'config_file\s*=\s*"([^"]+)"')
        if (-not $configMatch.Success) { continue }
        $agentConfigPath = Join-Path $codexHomePath $configMatch.Groups[1].Value
        if (-not (Test-Path -LiteralPath $agentConfigPath)) {
            $missingAgentConfigs.Add("$name -> $($configMatch.Groups[1].Value)") | Out-Null
        }
    }
    if ($missingAgentConfigs.Count -gt 0) {
        Add-Check -Name "agent-config-files" -Status "failed" -Detail ($missingAgentConfigs -join "; ")
    } else {
        Add-Check -Name "agent-config-files" -Status "passed" -Detail "All configured agent files exist."
    }
} else {
    Add-Check -Name "global-config" -Status "failed" -Detail "config.toml not found."
}

if (Test-Path -LiteralPath $capabilityPath) {
    try {
        $capabilities = Get-Content -LiteralPath $capabilityPath -Raw | ConvertFrom-Json
        if ($capabilities.schema -ne "codex-harness-capabilities-v1") {
            Add-Check -Name "capability-manifest" -Status "warning" -Detail "Unexpected schema: $($capabilities.schema)"
        } else {
            Add-Check -Name "capability-manifest" -Status "passed" -Detail "schema: $($capabilities.schema)"
        }
        $profileNames = @($capabilities.profiles.PSObject.Properties.Name | Sort-Object)
        if ($profileNames.Count -gt 0) {
            Add-Check -Name "capability-profiles" -Status "info" -Detail "profiles: $($profileNames -join ', ')"
        }
    } catch {
        Add-Check -Name "capability-manifest" -Status "failed" -Detail $_.Exception.Message
    }
} else {
    Add-Check -Name "capability-manifest" -Status "warning" -Detail "harness.capabilities.json not found."
}

$failed = @($checks | Where-Object { $_.status -eq "failed" })
$warnings = @($checks | Where-Object { $_.status -eq "warning" })
$status = if ($failed.Count -gt 0) { "failed" } elseif ($warnings.Count -gt 0) { "warning" } else { "passed" }

[ordered]@{
    schema = "codex-harness-surface-check-v1"
    status = $status
    created_at = (Get-Date).ToString("o")
    codex_home = $codexHomePath
    checks = $checks.ToArray()
} | ConvertTo-Json -Depth 8 -Compress
