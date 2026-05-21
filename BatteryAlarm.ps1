Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'

$AppName = 'Battery Alarm'
$AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $AppDir 'config.json'

$DefaultConfig = [ordered]@{
    LowBatteryLimit = 20
    HighBatteryLimit = 80
    CheckIntervalSeconds = 30
    NotificationIntervalSeconds = 60
}

function Save-DefaultConfig {
    $DefaultConfig | ConvertTo-Json | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
}

function Get-AppConfig {
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        Save-DefaultConfig
    }

    try {
        $raw = Get-Content -LiteralPath $ConfigPath -Raw
        $config = $raw | ConvertFrom-Json
    }
    catch {
        $backupPath = Join-Path $AppDir ("config.invalid.{0:yyyyMMddHHmmss}.json" -f (Get-Date))
        Move-Item -LiteralPath $ConfigPath -Destination $backupPath
        Save-DefaultConfig
        $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    }

    $low = [int]$config.LowBatteryLimit
    $high = [int]$config.HighBatteryLimit
    $check = [int]$config.CheckIntervalSeconds
    $notify = [int]$config.NotificationIntervalSeconds

    if ($low -lt 1 -or $low -gt 99) { $low = $DefaultConfig.LowBatteryLimit }
    if ($high -lt 1 -or $high -gt 100) { $high = $DefaultConfig.HighBatteryLimit }
    if ($check -lt 5) { $check = $DefaultConfig.CheckIntervalSeconds }
    if ($notify -lt 10) { $notify = $DefaultConfig.NotificationIntervalSeconds }

    [pscustomobject]@{
        LowBatteryLimit = $low
        HighBatteryLimit = $high
        CheckIntervalSeconds = $check
        NotificationIntervalSeconds = $notify
    }
}

function Get-BatterySnapshot {
    $powerStatus = [System.Windows.Forms.SystemInformation]::PowerStatus
    $percent = [int][Math]::Round($powerStatus.BatteryLifePercent * 100)

    [pscustomobject]@{
        Percent = $percent
        PowerLineStatus = $powerStatus.PowerLineStatus
    }
}

$Config = Get-AppConfig
$LastNotificationAt = [DateTime]::MinValue
$LastAlarmKind = ''

$Context = New-Object System.Windows.Forms.ApplicationContext
$Icon = New-Object System.Windows.Forms.NotifyIcon
$Icon.Icon = [System.Drawing.SystemIcons]::Information
$Icon.Text = $AppName
$Icon.Visible = $true

$Menu = New-Object System.Windows.Forms.ContextMenuStrip
$StatusItem = New-Object System.Windows.Forms.ToolStripMenuItem
$StatusItem.Enabled = $false
[void]$Menu.Items.Add($StatusItem)
[void]$Menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$ReloadItem = New-Object System.Windows.Forms.ToolStripMenuItem
$ReloadItem.Text = 'Reload config'
[void]$Menu.Items.Add($ReloadItem)

$ExitItem = New-Object System.Windows.Forms.ToolStripMenuItem
$ExitItem.Text = 'Exit'
[void]$Menu.Items.Add($ExitItem)
$Icon.ContextMenuStrip = $Menu

function Show-Notice($title, $message) {
    $Icon.BalloonTipTitle = $title
    $Icon.BalloonTipText = $message
    $Icon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Warning
    $Icon.ShowBalloonTip(10000)
}

function Update-StatusText($snapshot) {
    $plugged = $snapshot.PowerLineStatus -eq [System.Windows.Forms.PowerLineStatus]::Online
    $state = if ($plugged) { 'plugged in' } else { 'on battery' }
    $StatusItem.Text = "Battery $($snapshot.Percent)% - $state"
    $Icon.Text = "$AppName - $($snapshot.Percent)%"
}

function Test-Battery {
    try {
        $snapshot = Get-BatterySnapshot
        Update-StatusText $snapshot

        $pluggedIn = $snapshot.PowerLineStatus -eq [System.Windows.Forms.PowerLineStatus]::Online
        $unplugged = $snapshot.PowerLineStatus -eq [System.Windows.Forms.PowerLineStatus]::Offline
        $alarmKind = ''
        $title = ''
        $message = ''

        if ($unplugged -and $snapshot.Percent -le $Config.LowBatteryLimit) {
            $alarmKind = 'LowBattery'
            $title = 'Battery low'
            $message = "Battery is $($snapshot.Percent)%. Plug in the charger."
        }
        elseif ($pluggedIn -and $snapshot.Percent -ge $Config.HighBatteryLimit) {
            $alarmKind = 'HighBattery'
            $title = 'Battery charged'
            $message = "Battery is $($snapshot.Percent)%. Unplug the charger."
        }

        if ($alarmKind -eq '') {
            $script:LastAlarmKind = ''
            $script:LastNotificationAt = [DateTime]::MinValue
            return
        }

        $now = Get-Date
        $secondsSinceLastNotice = ($now - $script:LastNotificationAt).TotalSeconds
        if ($alarmKind -ne $script:LastAlarmKind -or $secondsSinceLastNotice -ge $Config.NotificationIntervalSeconds) {
            Show-Notice $title $message
            $script:LastAlarmKind = $alarmKind
            $script:LastNotificationAt = $now
        }
    }
    catch {
        Show-Notice 'Battery Alarm error' $_.Exception.Message
    }
}

$ReloadItem.Add_Click({
    $script:Config = Get-AppConfig
    $Timer.Interval = [Math]::Max(5, $Config.CheckIntervalSeconds) * 1000
    Test-Battery
})

$ExitItem.Add_Click({
    $Icon.Visible = $false
    $Icon.Dispose()
    $Context.ExitThread()
})

$Timer = New-Object System.Windows.Forms.Timer
$Timer.Interval = [Math]::Max(5, $Config.CheckIntervalSeconds) * 1000
$Timer.Add_Tick({ Test-Battery })
$Timer.Start()

Test-Battery
[System.Windows.Forms.Application]::Run($Context)
