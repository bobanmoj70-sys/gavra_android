# Registruje GavraOSRM_Watchdog: svaka 3 minuta proverava OSRM i Funnel DNS.
# Pokrenuti jednom kao isti korisnik (Bojan). Može da se ponavlja bez štete.

$ErrorActionPreference = "Stop"

$ServiceDir = $PSScriptRoot
$Watchdog = Join-Path $ServiceDir "osrm_watchdog.ps1"
$TaskName = "GavraOSRM_Watchdog"

if (-not (Test-Path $Watchdog)) {
    throw "Nedostaje $Watchdog"
}

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Watchdog`"" `
    -WorkingDirectory $ServiceDir

$repeat = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes 3) `
    -RepetitionDuration (New-TimeSpan -Days 9999)

$logon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

$principalHighest = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -LogonType Interactive `
    -RunLevel Highest

$principalLimited = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -LogonType Interactive `
    -RunLevel Limited

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 8)

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

$registered = $false
foreach ($principal in @($principalHighest, $principalLimited)) {
    try {
        Register-ScheduledTask `
            -TaskName $TaskName `
            -Action $action `
            -Trigger @($repeat, $logon) `
            -Principal $principal `
            -Settings $settings `
            -Description "Svaka 3 min proverava OSRM/proxy i javni Tailscale Funnel DNS. Reciklira Funnel ako 8.8.8.8 vrati NXDOMAIN." | Out-Null
        $registered = $true
        Write-Host "Task $TaskName je registrovan (RunLevel=$($principal.RunLevel))."
        break
    } catch {
        Write-Host "Register sa RunLevel=$($principal.RunLevel) nije uspeo: $($_.Exception.Message)"
    }
}

if (-not $registered) {
    throw "Ne mogu da registrujem $TaskName. Pokreni ovu skriptu kao Administrator."
}

Get-ScheduledTask -TaskName $TaskName | Format-Table TaskName, State -AutoSize
