# Registruje GavraOSRM_Watchdog: svakih 5 minuta proverava OSRM i Funnel DNS.
# Pokrenuti jednom kao isti korisnik (Bojan). Može da se ponavlja bez štete.

$ErrorActionPreference = "Stop"

$ServiceDir = $PSScriptRoot
$Watchdog = Join-Path $ServiceDir "osrm_watchdog.ps1"
$TaskName = "GavraOSRM_Watchdog"

if (-not (Test-Path $Watchdog)) {
    throw "Nedostaje $Watchdog"
}

$taskArgs = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $Watchdog

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument $taskArgs `
    -WorkingDirectory $ServiceDir

$repeat = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes 5) `
    -RepetitionDuration (New-TimeSpan -Days 9999)

$logon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

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

$registered = $false
foreach ($principal in @($principalLimited, $null)) {
    try {
        if ($null -ne $principal) {
            Register-ScheduledTask `
                -TaskName $TaskName `
                -Action $action `
                -Trigger @($repeat, $logon) `
                -Principal $principal `
                -Settings $settings `
                -Description "Svaki 5 min proverava OSRM/proxy i javni Tailscale Funnel DNS. Reciklira Funnel ako 8.8.8.8 vrati NXDOMAIN, i proaktivno refresuje funnel svakih ~20 min." `
                -Force | Out-Null
        } else {
            Register-ScheduledTask `
                -TaskName $TaskName `
                -Action $action `
                -Trigger @($repeat, $logon) `
                -Settings $settings `
                -Description "Svaki 5 min proverava OSRM/proxy i javni Tailscale Funnel DNS. Reciklira Funnel ako 8.8.8.8 vrati NXDOMAIN, i proaktivno refresuje funnel svakih ~20 min." `
                -Force | Out-Null
        }
        $registered = $true
        if ($null -ne $principal) {
            Write-Host "Task $TaskName je registrovan (RunLevel=$($principal.RunLevel))."
        } else {
            Write-Host "Task $TaskName je registrovan (fallback bez eksplicitnog principal-a)."
        }
        break
    } catch {
        if ($null -ne $principal) {
            Write-Host "Register sa RunLevel=$($principal.RunLevel) nije uspeo: $($_.Exception.Message)"
        } else {
            Write-Host "Fallback register nije uspeo: $($_.Exception.Message)"
        }
    }
}

if (-not $registered) {
    throw "Ne mogu da registrujem $TaskName. Pokreni ovu skriptu kao Administrator."
}

Get-ScheduledTask -TaskName $TaskName | Format-Table TaskName, State -AutoSize
