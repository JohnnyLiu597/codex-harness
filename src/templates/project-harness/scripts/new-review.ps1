param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Status = "completed",
    [string]$Reviewer = "codex",
    [string]$Summary = "",
    [string[]]$Findings = @(),
    [string[]]$Checks = @(),
    [string[]]$Evidence = @(),
    [string[]]$ResidualRisk = @(),
    [Alias("MakerIdentity")][string]$Maker = "",
    [Alias("CheckerIdentity")][string]$Checker = "",
    [Alias("LastVerifiedCommit")][string]$VerifiedCommit = ""
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$stamp = Get-Date -Format "yyyyMMdd-HHmmssfff"
$slug = ($Name -replace '[^a-zA-Z0-9]+', '-').Trim('-').ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($slug)) {
    $slug = "review"
}

$runDir = Join-Path $root ("artifacts\reviews\" + $stamp + "-" + $slug)
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$jsonPath = Join-Path $runDir "review.json"
$summaryPath = Join-Path $runDir "summary.md"
$createdAt = Get-Date

$branch = ""
$head = ""
try {
    $branch = (git -C $root branch --show-current 2>$null | Out-String).Trim()
    $head = (git -C $root rev-parse --short HEAD 2>$null | Out-String).Trim()
} catch {
    $branch = "unknown"
    $head = "unknown"
}

$resolvedChecker = if ([string]::IsNullOrWhiteSpace($Checker)) { $Reviewer } else { $Checker }
$makerCheckerSeparated = if (
    -not [string]::IsNullOrWhiteSpace($Maker) -and
    -not [string]::IsNullOrWhiteSpace($resolvedChecker)
) {
    -not $Maker.Equals($resolvedChecker, [System.StringComparison]::OrdinalIgnoreCase)
} else {
    $null
}

$record = [ordered]@{
    schema = "codex-review-v2"
    name = $Name
    status = $Status
    reviewer = $Reviewer
    maker = $Maker
    checker = $resolvedChecker
    maker_identity = $Maker
    checker_identity = $resolvedChecker
    maker_checker_separated = $makerCheckerSeparated
    verified_commit = $VerifiedCommit
    created_at = $createdAt.ToString("o")
    root = $root
    branch = $branch
    head = $head
    summary = $Summary
    findings = $Findings
    checks = $Checks
    evidence = $Evidence
    residual_risk = $ResidualRisk
}
$record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

function Format-Lines {
    param([string[]]$Lines)
    if ($Lines.Count -eq 0) { return "- None." }
    return (($Lines | ForEach-Object { "- $_" }) -join "`r`n")
}

$md = @"
# Review: $Name

- Status: $Status
- Reviewer: $Reviewer
- Maker: $Maker
- Checker: $resolvedChecker
- Maker/Checker Separated: $makerCheckerSeparated
- Verified Commit: $VerifiedCommit
- Branch: $branch
- Head: $head
- Created: $($createdAt.ToString("yyyy-MM-dd HH:mm:ss"))

## Summary

$Summary

## Findings

$(Format-Lines -Lines $Findings)

## Checks

$(Format-Lines -Lines $Checks)

## Evidence

$(Format-Lines -Lines $Evidence)

## Residual Risk

$(Format-Lines -Lines $ResidualRisk)
"@
Set-Content -LiteralPath $summaryPath -Value $md -Encoding UTF8

[ordered]@{
    status = "success"
    summary = "Created review record."
    artifacts = @($jsonPath, $summaryPath)
} | ConvertTo-Json -Depth 5 -Compress
