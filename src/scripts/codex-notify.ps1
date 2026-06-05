param()

$ErrorActionPreference = "SilentlyContinue"

$payload = [Console]::In.ReadToEnd()
$message = "Task completed."

if ($payload) {
    try {
        $json = $payload | ConvertFrom-Json
        if ($json.message) {
            $message = [string]$json.message
        } elseif ($json.summary) {
            $message = [string]$json.summary
        } elseif ($json.status) {
            $message = "Codex finished with status: $($json.status)"
        }
    } catch {
        $message = $payload.Trim()
    }
}

if ([string]::IsNullOrWhiteSpace($message)) {
    $message = "Task completed."
}

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $notify = New-Object System.Windows.Forms.NotifyIcon
    $notify.Icon = [System.Drawing.SystemIcons]::Information
    $notify.BalloonTipTitle = "Codex"
    $notify.BalloonTipText = $message
    $notify.Visible = $true
    $notify.ShowBalloonTip(4000)

    Start-Sleep -Seconds 5
    $notify.Dispose()
} catch {
    exit 0
}
