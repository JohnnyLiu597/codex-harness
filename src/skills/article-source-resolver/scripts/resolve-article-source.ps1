[CmdletBinding(DefaultParameterSetName = "File")]
param(
    [Parameter(Mandatory = $true, ParameterSetName = "Url")]
    [uri]$Url,

    [Parameter(Mandatory = $true, ParameterSetName = "File")]
    [string]$InputFile,

    [Parameter(ParameterSetName = "File")]
    [string]$SourceUrl = "",

    [Parameter(ParameterSetName = "File")]
    [string]$ContentTypeHint = "",

    [Parameter(ParameterSetName = "Url")]
    [switch]$AllowNetwork,

    [switch]$IncludeContent,

    [ValidateSet("Article", "Web")]
    [string]$Mode = "Article",

    [Parameter(ParameterSetName = "Url")]
    [string]$SaveHtmlPath = "",

    [string]$OutputPath = "",

    [ValidateRange(1, 120)]
    [int]$TimeoutSec = 25,

    [ValidateRange(0, 2)]
    [int]$Retries = 1,

    [ValidateRange(65536, 20971520)]
    [int]$MaxBytes = 8388608
)

$ErrorActionPreference = "Stop"

$python = Get-Command python -ErrorAction SilentlyContinue
$pyLauncher = Get-Command py -ErrorAction SilentlyContinue
if (-not $python -and -not $pyLauncher) {
    throw "Python 3 is required for article source resolution."
}

$resolver = Join-Path $PSScriptRoot "resolve_article_source.py"
if (-not (Test-Path -LiteralPath $resolver -PathType Leaf)) {
    throw "Article source resolver is missing: $resolver"
}

$arguments = @($resolver)
if ($PSCmdlet.ParameterSetName -eq "Url") {
    if (-not $AllowNetwork) {
        throw "Network acquisition requires the explicit -AllowNetwork switch."
    }
    $arguments += @("--url", $Url.AbsoluteUri, "--allow-network")
    if ($SaveHtmlPath) {
        $saveParent = Split-Path -Parent $SaveHtmlPath
        if ($saveParent) {
            New-Item -ItemType Directory -Force -Path $saveParent | Out-Null
        }
        $arguments += @("--save-html", $SaveHtmlPath)
    }
} else {
    $resolvedInput = (Resolve-Path -LiteralPath $InputFile).Path
    $arguments += @("--input-file", $resolvedInput)
    if ($SourceUrl) {
        $arguments += @("--source-url", $SourceUrl)
    }
    if ($ContentTypeHint) {
        $arguments += @("--content-type-hint", $ContentTypeHint)
    }
}

if ($IncludeContent) {
    $arguments += "--include-content"
}
$arguments += @("--mode", $Mode.ToLowerInvariant())
if ($OutputPath) {
    $outputParent = Split-Path -Parent $OutputPath
    if ($outputParent) {
        New-Item -ItemType Directory -Force -Path $outputParent | Out-Null
    }
    $arguments += @("--output", $OutputPath)
}

$arguments += @(
    "--timeout", [string]$TimeoutSec,
    "--retries", [string]$Retries,
    "--max-bytes", [string]$MaxBytes
)

if ($python) {
    & $python.Source @arguments
} else {
    & $pyLauncher.Source -3 @arguments
}

if ($LASTEXITCODE -ne 0) {
    throw "Article source resolver failed with exit code $LASTEXITCODE."
}
