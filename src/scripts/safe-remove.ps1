param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

$ErrorActionPreference = "Stop"
$Paths = New-Object System.Collections.Generic.List[string]
$TrashRoot = ""
$WhatIf = $false

for ($i = 0; $i -lt $Args.Count; $i++) {
    $item = $Args[$i]
    if ($item -eq "-TrashRoot") {
        $i += 1
        if ($i -ge $Args.Count) { throw "-TrashRoot requires a value." }
        $TrashRoot = $Args[$i]
    } elseif ($item -eq "-WhatIf") {
        $WhatIf = $true
    } elseif ($item -eq "-Paths") {
        $i += 1
        if ($i -ge $Args.Count) { throw "-Paths requires at least one value." }
        $Paths.Add($Args[$i]) | Out-Null
    } else {
        $Paths.Add($item) | Out-Null
    }
}

if ($Paths.Count -eq 0) {
    throw "At least one path is required."
}

function Get-DefaultTrashRoot {
    param([Parameter(Mandatory = $true)][string]$StartPath)

    $base = if (Test-Path -LiteralPath $StartPath -PathType Container) {
        (Resolve-Path -LiteralPath $StartPath).Path
    } else {
        Split-Path -Parent (Resolve-Path -LiteralPath $StartPath).Path
    }

    try {
        $gitRoot = git -C $base rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($gitRoot)) {
            return (Join-Path $gitRoot ".codex-trash")
        }
    } catch {
    }

    return (Join-Path "C:\Users\Johnny Liu\.codex" ".codex-trash")
}

function Get-UniqueDestination {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$Leaf
    )

    $candidate = Join-Path $Directory $Leaf
    if (-not (Test-Path -LiteralPath $candidate)) {
        return $candidate
    }

    $i = 1
    while ($true) {
        $next = Join-Path $Directory "$Leaf.$i"
        if (-not (Test-Path -LiteralPath $next)) {
            return $next
        }
        $i += 1
    }
}

$moved = New-Object System.Collections.Generic.List[object]
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"

foreach ($path in $Paths) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Path not found: $path"
    }

    $resolved = (Resolve-Path -LiteralPath $path).Path
    $root = if ([string]::IsNullOrWhiteSpace($TrashRoot)) {
        Get-DefaultTrashRoot -StartPath $resolved
    } else {
        $TrashRoot
    }
    $targetDir = Join-Path $root $stamp
    $leaf = Split-Path -Leaf $resolved
    $destination = Get-UniqueDestination -Directory $targetDir -Leaf $leaf

    if (-not $WhatIf) {
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
        Move-Item -LiteralPath $resolved -Destination $destination
    }

    $moved.Add([pscustomobject]@{
        source = $resolved
        destination = $destination
        moved = -not [bool]$WhatIf
    }) | Out-Null
}

[ordered]@{
    status = "success"
    summary = "Moved files to trash staging folder. Only the user should empty this folder."
    trash_root = if ($moved.Count -gt 0) { Split-Path -Parent (Split-Path -Parent $moved[0].destination) } else { $TrashRoot }
    items = $moved.ToArray()
} | ConvertTo-Json -Depth 8 -Compress
