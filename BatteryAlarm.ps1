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
    AlarmSoundDurationSeconds = 12
    AlarmSoundVolumePercent = 100
    SnoozeMinutes = 5
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
    $soundDuration = [int]$config.AlarmSoundDurationSeconds
    $soundVolume = [int]$config.AlarmSoundVolumePercent
    $snooze = [int]$config.SnoozeMinutes

    if ($low -lt 1 -or $low -gt 99) { $low = $DefaultConfig.LowBatteryLimit }
    if ($high -lt 1 -or $high -gt 100) { $high = $DefaultConfig.HighBatteryLimit }
    if ($check -lt 5) { $check = $DefaultConfig.CheckIntervalSeconds }
    if ($notify -lt 10) { $notify = $DefaultConfig.NotificationIntervalSeconds }
    if ($soundDuration -lt 1 -or $soundDuration -gt 60) { $soundDuration = $DefaultConfig.AlarmSoundDurationSeconds }
    if ($soundVolume -lt 1 -or $soundVolume -gt 100) { $soundVolume = $DefaultConfig.AlarmSoundVolumePercent }
    if ($snooze -lt 1 -or $snooze -gt 1440) { $snooze = $DefaultConfig.SnoozeMinutes }

    [pscustomobject]@{
        LowBatteryLimit = $low
        HighBatteryLimit = $high
        CheckIntervalSeconds = $check
        NotificationIntervalSeconds = $notify
        AlarmSoundDurationSeconds = $soundDuration
        AlarmSoundVolumePercent = $soundVolume
        SnoozeMinutes = $snooze
    }
}

function New-AlarmSoundFile($durationSeconds, $volumePercent) {
    $safeDuration = [Math]::Max(1, [Math]::Min(60, [int]$durationSeconds))
    $safeVolume = [Math]::Max(1, [Math]::Min(100, [int]$volumePercent))
    $soundPath = Join-Path $AppDir ("alarm.{0}s.{1}pct.wav" -f $safeDuration, $safeVolume)

    if (Test-Path -LiteralPath $soundPath) {
        return $soundPath
    }

    $sampleRate = 44100
    $bitsPerSample = 16
    $channelCount = 1
    $sampleCount = $sampleRate * $safeDuration
    $blockAlign = [int]($channelCount * $bitsPerSample / 8)
    $byteRate = $sampleRate * $blockAlign
    $dataSize = $sampleCount * $blockAlign
    $amplitude = [int16]([Int16]::MaxValue * 0.85 * ($safeVolume / 100.0))
    $writer = $null

    try {
        $stream = [System.IO.File]::Open($soundPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $writer = New-Object System.IO.BinaryWriter($stream)

        $writer.Write([System.Text.Encoding]::ASCII.GetBytes('RIFF'))
        $writer.Write([int](36 + $dataSize))
        $writer.Write([System.Text.Encoding]::ASCII.GetBytes('WAVE'))
        $writer.Write([System.Text.Encoding]::ASCII.GetBytes('fmt '))
        $writer.Write([int]16)
        $writer.Write([int16]1)
        $writer.Write([int16]$channelCount)
        $writer.Write([int]$sampleRate)
        $writer.Write([int]$byteRate)
        $writer.Write([int16]$blockAlign)
        $writer.Write([int16]$bitsPerSample)
        $writer.Write([System.Text.Encoding]::ASCII.GetBytes('data'))
        $writer.Write([int]$dataSize)

        for ($i = 0; $i -lt $sampleCount; $i++) {
            $elapsed = $i / $sampleRate
            $cyclePosition = $elapsed % 0.7
            $frequency = if ($cyclePosition -lt 0.35) { 880 } else { 660 }
            $gate = if (($elapsed % 1.4) -lt 1.15) { 1.0 } else { 0.0 }
            $sample = [int16]($amplitude * $gate * [Math]::Sin(2 * [Math]::PI * $frequency * $elapsed))
            $writer.Write($sample)
        }
    }
    finally {
        if ($writer -ne $null) {
            $writer.Dispose()
        }
    }

    return $soundPath
}

function Play-AlarmSound {
    try {
        $soundPath = New-AlarmSoundFile $Config.AlarmSoundDurationSeconds $Config.AlarmSoundVolumePercent

        Stop-AlarmSound

        $script:AlarmPlayer = New-Object System.Media.SoundPlayer($soundPath)
        $script:AlarmPlayer.Load()
        $script:AlarmPlayer.Play()
    }
    catch {
        [System.Media.SystemSounds]::Exclamation.Play()
    }
}

function Stop-AlarmSound {
    if ($script:AlarmPlayer -ne $null) {
        $script:AlarmPlayer.Stop()
        $script:AlarmPlayer.Dispose()
        $script:AlarmPlayer = $null
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
$AlarmPlayer = $null
$SnoozedUntil = [DateTime]::MinValue

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
    Play-AlarmSound
}

function Snooze-Alarm {
    $script:SnoozedUntil = (Get-Date).AddMinutes($Config.SnoozeMinutes)
    Stop-AlarmSound
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
            Stop-AlarmSound
            $script:SnoozedUntil = [DateTime]::MinValue
            $script:LastAlarmKind = ''
            $script:LastNotificationAt = [DateTime]::MinValue
            return
        }

        $now = Get-Date
        if ($script:SnoozedUntil -gt $now) {
            return
        }

        $script:SnoozedUntil = [DateTime]::MinValue
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
    Stop-AlarmSound
    $Icon.Visible = $false
    $Icon.Dispose()
    $Context.ExitThread()
})

$Timer = New-Object System.Windows.Forms.Timer
$Timer.Interval = [Math]::Max(5, $Config.CheckIntervalSeconds) * 1000
$Timer.Add_Tick({ Test-Battery })
$Timer.Start()

$PowerModeChangedHandler = {
    Test-Battery
}
[Microsoft.Win32.SystemEvents]::add_PowerModeChanged($PowerModeChangedHandler)
$Icon.Add_BalloonTipClosed({ Snooze-Alarm })

$Context.add_ThreadExit({
    [Microsoft.Win32.SystemEvents]::remove_PowerModeChanged($PowerModeChangedHandler)
    Stop-AlarmSound
})

Test-Battery
[System.Windows.Forms.Application]::Run($Context)
