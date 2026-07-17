# Podesi OSRM server (Docker) i Tailscale Funnel rute da se automatski
# ponovo pokrenu/primene pri logovanju u Windows.
# Pokreni ovu skriptu kao Administrator (jednom).

$ErrorActionPreference = "Stop"

$TaskName = "GavraOSRM_Autostart"
$ScriptPath = 'c:\Users\Bojan\gavra_android\ml-service\start_osrm_server.ps1'

if (-not (Test-Path $ScriptPath)) {
    Write-Error "Skripta nije pronađena: $ScriptPath"
    exit 1
}

# Ukloni postojeći task ako postoji
$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Uklanjam postojeći zadatak '$TaskName'..."
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# Akcija: pokreni PowerShell i izvrši skriptu
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""

# Trigger: pri logovanju bilo kog korisnika, sa malim odlaganjem da Docker Desktop stigne da krene
$Trigger = New-ScheduledTaskTrigger -AtLogOn
$Trigger.Delay = "PT30S"

$Principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest

$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable:$false -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Force

Write-Host "Zadatak '$TaskName' je uspešno kreiran." -ForegroundColor Green
Write-Host "OSRM server i Tailscale rute će se automatski proveriti/pokrenuti pri prijavi u Windows." -ForegroundColor Green
Write-Host ""
Write-Host "Korisne komande:"
Write-Host "  Pokreni odmah:  Start-ScheduledTask -TaskName '$TaskName'"
Write-Host "  Zaustavi:       Stop-ScheduledTask -TaskName '$TaskName'"
Write-Host "  Ukloni:         Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false"
Write-Host "  Log fajl:       c:\Users\Bojan\gavra_android\ml-service\osrm_autostart.log"
