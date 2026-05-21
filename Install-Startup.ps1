$ErrorActionPreference = 'Stop'

$appDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$startupDir = [Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startupDir 'Battery Alarm.lnk'
$targetPath = Join-Path $appDir 'Start-BatteryAlarm.vbs'

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $targetPath
$shortcut.WorkingDirectory = $appDir
$shortcut.WindowStyle = 7
$shortcut.Description = 'Start Battery Alarm with no terminal window'
$shortcut.Save()

Write-Host "Installed startup shortcut: $shortcutPath"
