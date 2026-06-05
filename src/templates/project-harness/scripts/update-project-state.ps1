param(
    [Parameter(Mandatory = $true)][string]$Summary,
    [string[]]$ContextLines = @(),
    [string[]]$MemoryLines = @()
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

function Update-Block {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$StartMarker,
        [Parameter(Mandatory = $true)][string]$EndMarker,
        [Parameter(Mandatory = $true)][string]$Block
    )

    $content = Get-Content -LiteralPath $Path -Raw
    $pattern = [regex]::Escape($StartMarker) + '.*' + [regex]::Escape($EndMarker)
    $options = [System.Text.RegularExpressions.RegexOptions]::Singleline

    if ([regex]::IsMatch($content, $pattern, $options)) {
        $updated = [regex]::Replace(
            $content,
            $pattern,
            $Block,
            $options
        )
    } else {
        $separator = if ($content.EndsWith("`r`n")) { "" } else { "`r`n" }
        $updated = $content + $separator + "`r`n" + $Block + "`r`n"
    }

    Set-Content -LiteralPath $Path -Value $updated -Encoding UTF8
}

if ($ContextLines.Count -eq 0) {
    $ContextLines = @($Summary)
}

if ($MemoryLines.Count -eq 0) {
    $MemoryLines = @($Summary)
}

$contextBody = @()
$contextBody += "<!-- codex-state:start -->"
$contextBody += "## Session Log"
$contextBody += ""
$contextBody += "- $stamp - $Summary"
foreach ($line in $ContextLines) {
    if (-not [string]::IsNullOrWhiteSpace($line)) {
        $contextBody += "- $line"
    }
}
$contextBody += "<!-- codex-state:end -->"

$memoryBody = @()
$memoryBody += "<!-- codex-memory:start -->"
$memoryBody += "## Recent Facts"
$memoryBody += ""
foreach ($line in $MemoryLines) {
    if (-not [string]::IsNullOrWhiteSpace($line)) {
        $memoryBody += "- $stamp - $line"
    }
}
$memoryBody += "<!-- codex-memory:end -->"

Update-Block -Path (Join-Path $root "CONTEXT.md") -StartMarker "<!-- codex-state:start -->" -EndMarker "<!-- codex-state:end -->" -Block ($contextBody -join "`r`n")
Update-Block -Path (Join-Path $root "MEMORY.md") -StartMarker "<!-- codex-memory:start -->" -EndMarker "<!-- codex-memory:end -->" -Block ($memoryBody -join "`r`n")

[ordered]@{
    status = "success"
    summary = "Updated CONTEXT.md and MEMORY.md."
    next_actions = @(
        "Keep the summary short and stable.",
        "Use this after substantial work or before pausing."
    )
    artifacts = @(
        (Join-Path $root "CONTEXT.md"),
        (Join-Path $root "MEMORY.md")
    )
} | ConvertTo-Json -Depth 5 -Compress
