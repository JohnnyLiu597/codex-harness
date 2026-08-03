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

    [Parameter(ParameterSetName = "Url")]
    [string]$SaveResponsePath = "",

    [string]$OutputPath = "",

    [ValidateRange(1, 120)]
    [int]$TimeoutSec = 25,

    [ValidateRange(0, 2)]
    [int]$Retries = 1,

    [ValidateRange(65536, 20971520)]
    [int]$MaxBytes = 8388608
)

$ErrorActionPreference = "Stop"

$coreResolver = Join-Path $env:USERPROFILE ".codex\skills\article-source-resolver\scripts\resolve-article-source.ps1"
if (-not (Test-Path -LiteralPath $coreResolver -PathType Leaf)) {
    throw "Core web acquisition resolver is missing: $coreResolver"
}

$arguments = @{
    Mode = "Web"
    TimeoutSec = $TimeoutSec
    Retries = $Retries
    MaxBytes = $MaxBytes
}

if ($PSCmdlet.ParameterSetName -eq "Url") {
    $arguments.Url = $Url
    $arguments.AllowNetwork = $AllowNetwork
    if ($SaveResponsePath) {
        $arguments.SaveHtmlPath = $SaveResponsePath
    }
} else {
    $arguments.InputFile = $InputFile
    if ($SourceUrl) {
        $arguments.SourceUrl = $SourceUrl
    }
    if ($ContentTypeHint) {
        $arguments.ContentTypeHint = $ContentTypeHint
    }
}

if ($IncludeContent) {
    $arguments.IncludeContent = $true
}
if ($OutputPath) {
    $arguments.OutputPath = $OutputPath
}

& $coreResolver @arguments
