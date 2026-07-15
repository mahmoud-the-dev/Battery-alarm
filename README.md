# Battery Alarm

A small Windows background tray app that reminds you to plug or unplug the charger based on battery level.

## Behavior

- If the charger is unplugged and battery is at or below `LowBatteryLimit`, it sends a notification and plays a loud low-battery alarm sound every minute until the charger is plugged in.
- If the charger is plugged in and battery is at or above `HighBatteryLimit`, it sends a notification and plays a higher full-battery alarm sound every minute until the charger is unplugged.
- Closing a notification stops the alarm sound and snoozes battery alerts for `SnoozeMinutes`.
- The app runs in the Windows notification area. Right-click the tray icon to reload config or exit.
- Alarm sounds are generated automatically as WAV files in the app folder the first time each one is needed.

## Run

Double-click `Start-BatteryAlarm.vbs`.

This starts the tray app without opening a terminal window. `Start-BatteryAlarm.bat` is kept as a simple fallback launcher.

## Configure

Edit `config.json`:

```json
{
  "LowBatteryLimit": 20,
  "HighBatteryLimit": 80,
  "CheckIntervalSeconds": 30,
  "NotificationIntervalSeconds": 60,
  "AlarmSoundDurationSeconds": 12,
  "AlarmSoundVolumePercent": 100,
  "SnoozeMinutes": 5
}
```

Right-click the tray icon and choose `Reload config` after changing the file.

`AlarmSoundDurationSeconds` can be set from `1` to `60`. `AlarmSoundVolumePercent` can be set from `1` to `100`.
`SnoozeMinutes` can be set from `1` to `1440`.

## Start With Windows

Run this once in PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Startup.ps1
```

To remove it from startup:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-Startup.ps1
```
