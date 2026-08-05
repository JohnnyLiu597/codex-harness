param(
    [string]$CodexHome = "$env:USERPROFILE\.codex",
    [string]$ProjectRoot = "",
    [switch]$DryRun,
    [switch]$NoBackup,
    [string]$TransactionRoot = "",
    [string]$RollbackManifest = ""
)

$ErrorActionPreference = "Stop"

function Get-StringSha256 {
    param([AllowEmptyString()][string]$Value)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-JsonAtomically {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $tempPath = Join-Path $parent ((Split-Path -Leaf $Path) + ".tmp-" + [guid]::NewGuid().ToString("N"))
    $encoding = New-Object System.Text.UTF8Encoding($false)
    try {
        [System.IO.File]::WriteAllText($tempPath, ($Value | ConvertTo-Json -Depth 12), $encoding)
        Move-Item -LiteralPath $tempPath -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
            Remove-Item -LiteralPath $tempPath -Force
        }
    }
}

if (-not (Test-Path -LiteralPath $CodexHome -PathType Container)) {
    throw "Codex home does not exist: $CodexHome"
}
$CodexHome = [System.IO.Path]::GetFullPath($CodexHome)
$script:codexRootPath = $CodexHome
$script:codexRootPrefix = $CodexHome.TrimEnd('\') + '\'
$codexHomeFingerprint = Get-StringSha256 -Value $CodexHome.ToLowerInvariant()

function Assert-InCodexHome {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full -ne $script:codexRootPath -and
        -not $full.StartsWith($script:codexRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to write outside Codex home: $full"
    }

    $cursor = Split-Path -Parent $full
    while ($cursor -and $cursor -ne $script:codexRootPath) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing to traverse a runtime reparse point: $cursor"
            }
        }
        $next = Split-Path -Parent $cursor
        if (-not $next -or $next -eq $cursor) { break }
        $cursor = $next
    }
}

function Get-RelativeRuntimePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = [System.IO.Path]::GetFullPath($Path)
    Assert-InCodexHome -Path $full
    return $full.Substring($script:codexRootPrefix.Length)
}

function Test-PrivateRuntimeTarget {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $segments = $RelativePath -split '[\\/]'
    $cursor = $CodexHome
    for ($index = 0; $index -lt ($segments.Count - 1); $index++) {
        $cursor = Join-Path $cursor $segments[$index]
        if (Test-Path -LiteralPath (Join-Path $cursor ".codex-private") -PathType Leaf) {
            return $true
        }
    }
    return $false
}

function Remove-EmptyCreatedDirectories {
    param([object[]]$Entries)

    $directories = @($Entries |
        ForEach-Object { @($_.created_directories) } |
        Where-Object { $_ } |
        Sort-Object @{ Expression = { ([string]$_).Length }; Descending = $true } -Unique)
    foreach ($relative in $directories) {
        $path = Join-Path $CodexHome ([string]$relative)
        Assert-InCodexHome -Path $path
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { continue }
        if (@(Get-ChildItem -LiteralPath $path -Force).Count -eq 0) {
            Remove-Item -LiteralPath $path -Force
        }
    }
}

function Invoke-TransactionRollback {
    param(
        [Parameter(Mandatory = $true)]$Transaction,
        [Parameter(Mandatory = $true)][string]$ManifestPath
    )

    $transactionRootPath = Split-Path -Parent $ManifestPath
    $restored = 0
    $removed = 0
    $Transaction.rollback.attempted = $true
    $Transaction.rollback.started_at = (Get-Date).ToUniversalTime().ToString("o")
    $Transaction.rollback.status = "running"
    Write-JsonAtomically -Path $ManifestPath -Value $Transaction

    try {
        foreach ($entry in @($Transaction.files)) {
            $relative = [string]$entry.relative_path
            $target = Join-Path $CodexHome $relative
            Assert-InCodexHome -Path $target
            if ([bool]$entry.target_existed) {
                $backup = Join-Path $transactionRootPath ([string]$entry.backup_relative_path)
                if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) {
                    throw "Transaction backup is missing for $relative"
                }
                $backupHash = Get-FileSha256 -Path $backup
                if ($backupHash -ne [string]$entry.target_sha256_before) {
                    throw "Transaction backup hash mismatch for $relative"
                }
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
                Copy-Item -LiteralPath $backup -Destination $target -Force
                if ((Get-FileSha256 -Path $target) -ne [string]$entry.target_sha256_before) {
                    throw "Rollback restore hash mismatch for $relative"
                }
                $entry.rollback_state = "restored"
                $restored++
            } else {
                if (Test-Path -LiteralPath $target -PathType Leaf) {
                    Remove-Item -LiteralPath $target -Force
                    $removed++
                } elseif (Test-Path -LiteralPath $target) {
                    throw "Rollback target is no longer a file: $relative"
                }
                $entry.rollback_state = "removed"
            }
        }
        Remove-EmptyCreatedDirectories -Entries @($Transaction.files)
        $Transaction.status = "rolled-back"
        $Transaction.rollback.status = "rolled-back"
        $Transaction.rollback.completed_at = (Get-Date).ToUniversalTime().ToString("o")
        $Transaction.rollback.restored_files = $restored
        $Transaction.rollback.removed_files = $removed
        Write-JsonAtomically -Path $ManifestPath -Value $Transaction
    } catch {
        $Transaction.status = "rollback-failed"
        $Transaction.rollback.status = "rollback-failed"
        $Transaction.rollback.completed_at = (Get-Date).ToUniversalTime().ToString("o")
        $Transaction.rollback.error_sha256 = Get-StringSha256 -Value $_.Exception.Message
        Write-JsonAtomically -Path $ManifestPath -Value $Transaction
        throw
    }

    return [pscustomobject]@{
        restored = $restored
        removed = $removed
    }
}

if ($RollbackManifest) {
    if ($DryRun -or $NoBackup -or $TransactionRoot) {
        throw "-RollbackManifest cannot be combined with -DryRun, -NoBackup, or -TransactionRoot."
    }
    $manifestPath = (Resolve-Path -LiteralPath $RollbackManifest).Path
    $transaction = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ([string]$transaction.schema -ne "codex-harness-sync-transaction-v2") {
        throw "Unsupported sync transaction manifest schema."
    }
    if ([string]$transaction.codex_home_sha256 -ne $codexHomeFingerprint) {
        throw "Transaction manifest belongs to a different Codex home."
    }
    $rollbackResult = Invoke-TransactionRollback -Transaction $transaction -ManifestPath $manifestPath
    [ordered]@{
        status = "rolled-back"
        summary = "Runtime sync transaction rolled back."
        codex_home = $CodexHome
        transaction_manifest = $manifestPath
        restored_files = $rollbackResult.restored
        removed_files = $rollbackResult.removed
        source_fingerprint = [string]$transaction.source_fingerprint
    } | ConvertTo-Json -Depth 8 -Compress
    return
}

if (-not $ProjectRoot) {
    $ProjectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
} else {
    if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
        throw "Project root does not exist: $ProjectRoot"
    }
    $ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
}

$srcRoot = Join-Path $ProjectRoot "src"
if (-not (Test-Path -LiteralPath $srcRoot -PathType Container)) {
    throw "Missing source payload: $srcRoot"
}
$srcRoot = [System.IO.Path]::GetFullPath($srcRoot)
$srcPrefix = $srcRoot.TrimEnd('\') + '\'

if ($NoBackup -and $TransactionRoot) {
    throw "-NoBackup cannot be combined with -TransactionRoot."
}

$excludedDirectoryNames = @(
    "__pycache__",
    ".codex-trash",
    ".sandbox",
    ".sandbox-bin",
    ".sandbox-secrets",
    ".tmp",
    "tmp",
    "plugins",
    "plugin",
    "cache",
    "caches",
    "session",
    "sessions",
    "archived_sessions",
    "log",
    "logs",
    "hook-logs",
    "browser",
    "browser-state",
    "browser_state",
    "computer-use",
    "process_manager",
    "harness-health",
    "harness-changes",
    "harness-learning",
    "skills.archived",
    "agents.archived",
    "backups",
    "archived",
    "database",
    "databases"
)
$excludedFileNames = @("auth.json", "config.toml", ".sync-manifest.json")
$excludedDatabaseExtensions = @(".db", ".db3", ".sdb", ".db-wal", ".db-shm")

function Test-ExcludedSourceFile {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$File,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [string[]]$AdditionalExcludedDirectories = @()
    )

    if (($File.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Source payload contains a reparse-point file: $RelativePath"
    }
    $segments = $RelativePath -split '[\\/]'
    $allExcludedDirectories = @($excludedDirectoryNames) + @($AdditionalExcludedDirectories)
    if (@($segments | Select-Object -First ([math]::Max(0, $segments.Count - 1)) | Where-Object {
        $_ -in $allExcludedDirectories -or $_ -like "backup-*"
    }).Count -gt 0) { return $true }
    if ($File.Name -in $excludedFileNames) { return $true }
    if ($File.Name -eq ".codex-private" -or $File.Name -match '(?i)\.bak(?:[-.].*)?$|\.backup(?:[-.].*)?$|~$') { return $true }
    if ($File.Name -like "*.sqlite*" -or $File.Extension -in @(".pyc", ".pyo") + $excludedDatabaseExtensions) { return $true }
    return $false
}

$payloadFiles = New-Object System.Collections.Generic.List[object]
function Add-PayloadFile {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $source = Join-Path $srcRoot $RelativePath
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { return }
    $file = Get-Item -LiteralPath $source -Force
    if (Test-ExcludedSourceFile -File $file -RelativePath $RelativePath) { return }
    $payloadFiles.Add([pscustomobject]@{
        relative_path = $RelativePath
        source_path = $file.FullName
        source_sha256 = Get-FileSha256 -Path $file.FullName
    }) | Out-Null
}

function Add-PayloadDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [string[]]$AdditionalExcludedDirectories = @()
    )

    $source = Join-Path $srcRoot $RelativePath
    if (-not (Test-Path -LiteralPath $source -PathType Container)) { return }
    foreach ($file in @(Get-ChildItem -LiteralPath $source -Recurse -Force -File | Sort-Object FullName)) {
        $fullRelative = $file.FullName.Substring($srcPrefix.Length)
        if (Test-ExcludedSourceFile -File $file -RelativePath $fullRelative -AdditionalExcludedDirectories $AdditionalExcludedDirectories) { continue }
        $payloadFiles.Add([pscustomobject]@{
            relative_path = $fullRelative
            source_path = $file.FullName
            source_sha256 = Get-FileSha256 -Path $file.FullName
        }) | Out-Null
    }
}

foreach ($file in @("AGENTS.md", "CODEX.md", "harness.capabilities.json", "harness.components.json", "hooks.json")) {
    Add-PayloadFile -RelativePath $file
}
Add-PayloadFile -RelativePath "automations\harness\automation.toml.template"
foreach ($directory in @("agents", "docs", "rules", "scripts", "templates", "skills")) {
    Add-PayloadDirectory -RelativePath $directory
}
Add-PayloadDirectory -RelativePath "harness-evals" -AdditionalExcludedDirectories @("runs")

$payloadFiles = @($payloadFiles | Sort-Object relative_path -Unique)
$fingerprintLines = @($payloadFiles | ForEach-Object {
    ([string]$_.relative_path).Replace('\', '/').ToLowerInvariant() + ":" + [string]$_.source_sha256
})
$sourceFingerprint = Get-StringSha256 -Value ($fingerprintLines -join "`n")

$plan = @($payloadFiles | Where-Object { -not (Test-PrivateRuntimeTarget -RelativePath ([string]$_.relative_path)) })
$copiedCategories = @($plan | ForEach-Object {
    (([string]$_.relative_path) -split '[\\/]')[0]
} | Sort-Object -Unique)

if ($DryRun) {
    [ordered]@{
        status = "dry-run"
        summary = "Runtime sync preview completed."
        codex_home = $CodexHome
        source_root = $srcRoot
        copied = $copiedCategories
        planned_file_count = $plan.Count
        source_file_count = $payloadFiles.Count
        source_fingerprint = $sourceFingerprint
        private_targets_preserved = $payloadFiles.Count - $plan.Count
        automation_template = "automations\harness\automation.toml.template"
        automation_note = "The source template is synced to runtime, but Codex App automation registration still requires the app automation surface."
        backup = ""
        transaction_manifest = ""
    } | ConvertTo-Json -Depth 8 -Compress
    return
}

$transaction = $null
$manifestPath = ""
$transactionRootPath = ""
if (-not $NoBackup) {
    if ($TransactionRoot) {
        $transactionRootPath = [System.IO.Path]::GetFullPath($TransactionRoot)
        if (Test-Path -LiteralPath $transactionRootPath) {
            $transactionRootPath = (Resolve-Path -LiteralPath $transactionRootPath).Path
        }
    } else {
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $transactionRootPath = Join-Path $CodexHome ("backup-$stamp-" + [guid]::NewGuid().ToString("N").Substring(0, 8) + "-codex-harness-sync")
    }
    New-Item -ItemType Directory -Force -Path $transactionRootPath | Out-Null
    $manifestPath = Join-Path $transactionRootPath "sync-transaction.json"
    if (Test-Path -LiteralPath $manifestPath) {
        throw "Transaction manifest already exists: $manifestPath"
    }

    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($record in $plan) {
        $relative = [string]$record.relative_path
        $target = Join-Path $CodexHome $relative
        Assert-InCodexHome -Path $target
        if (Test-Path -LiteralPath $target -PathType Container) {
            throw "Runtime target is a directory, expected a file: $relative"
        }

        $targetExisted = Test-Path -LiteralPath $target -PathType Leaf
        $backupRelative = ""
        $targetHashBefore = ""
        if ($targetExisted) {
            $targetItem = Get-Item -LiteralPath $target -Force
            if (($targetItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing to replace a runtime reparse-point file: $relative"
            }
            $targetHashBefore = Get-FileSha256 -Path $target
            $backupRelative = Join-Path "files" $relative
            $backupPath = Join-Path $transactionRootPath $backupRelative
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupPath) | Out-Null
            Copy-Item -LiteralPath $target -Destination $backupPath -Force
            if ((Get-FileSha256 -Path $backupPath) -ne $targetHashBefore) {
                throw "Transaction backup hash mismatch for $relative"
            }
        }

        $createdDirectories = New-Object System.Collections.Generic.List[string]
        $cursor = Split-Path -Parent $target
        while ($cursor -and $cursor -ne $CodexHome -and -not (Test-Path -LiteralPath $cursor)) {
            $createdDirectories.Add((Get-RelativeRuntimePath -Path $cursor)) | Out-Null
            $next = Split-Path -Parent $cursor
            if (-not $next -or $next -eq $cursor) { break }
            $cursor = $next
        }

        $entries.Add([ordered]@{
            relative_path = $relative
            source_sha256 = [string]$record.source_sha256
            target_existed = [bool]$targetExisted
            target_sha256_before = $targetHashBefore
            backup_relative_path = $backupRelative
            created_directories = $createdDirectories.ToArray()
            state = "prepared"
            target_sha256_after = ""
            rollback_state = "not-needed"
        }) | Out-Null
    }

    $transaction = [ordered]@{
        schema = "codex-harness-sync-transaction-v2"
        transaction_id = [guid]::NewGuid().ToString("N")
        created_at = (Get-Date).ToUniversalTime().ToString("o")
        completed_at = $null
        status = "prepared"
        codex_home_sha256 = $codexHomeFingerprint
        source_fingerprint = $sourceFingerprint
        source_file_count = $payloadFiles.Count
        planned_file_count = $plan.Count
        files = $entries.ToArray()
        rollback = [ordered]@{
            attempted = $false
            status = "not-needed"
            started_at = $null
            completed_at = $null
            restored_files = 0
            removed_files = 0
            error_sha256 = ""
        }
    }
    Write-JsonAtomically -Path $manifestPath -Value $transaction
}

try {
    if ($transaction) {
        $transaction.status = "installing"
        Write-JsonAtomically -Path $manifestPath -Value $transaction
    }
    foreach ($record in $plan) {
        $relative = [string]$record.relative_path
        $target = Join-Path $CodexHome $relative
        Assert-InCodexHome -Path $target
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Copy-Item -LiteralPath ([string]$record.source_path) -Destination $target -Force
        $targetHash = Get-FileSha256 -Path $target
        if ($targetHash -ne [string]$record.source_sha256) {
            throw "Installed file hash mismatch for $relative"
        }
        if ($transaction) {
            $entry = @($transaction.files | Where-Object { [string]$_.relative_path -eq $relative })[0]
            $entry.state = "installed"
            $entry.target_sha256_after = $targetHash
            Write-JsonAtomically -Path $manifestPath -Value $transaction
        }
    }
    if ($transaction) {
        $transaction.status = "installed"
        $transaction.completed_at = (Get-Date).ToUniversalTime().ToString("o")
        Write-JsonAtomically -Path $manifestPath -Value $transaction
    }
} catch {
    $installError = $_
    if ($transaction) {
        $transaction.status = "install-failed"
        $transaction.install_error_sha256 = Get-StringSha256 -Value $installError.Exception.Message
        Write-JsonAtomically -Path $manifestPath -Value $transaction
        try {
            Invoke-TransactionRollback -Transaction $transaction -ManifestPath $manifestPath | Out-Null
        } catch {
            throw "Runtime sync failed and automatic rollback failed. Transaction: $manifestPath"
        }
        throw "Runtime sync failed and was rolled back. Transaction: $manifestPath"
    }
    throw
}

[ordered]@{
    status = "success"
    summary = "Source payload synced to runtime."
    codex_home = $CodexHome
    source_root = $srcRoot
    copied = $copiedCategories
    copied_file_count = $plan.Count
    source_file_count = $payloadFiles.Count
    source_fingerprint = $sourceFingerprint
    private_targets_preserved = $payloadFiles.Count - $plan.Count
    automation_template = "automations\harness\automation.toml.template"
    automation_note = "The source template is synced to runtime, but Codex App automation registration still requires the app automation surface."
    backup = $transactionRootPath
    transaction_manifest = $manifestPath
} | ConvertTo-Json -Depth 8 -Compress
