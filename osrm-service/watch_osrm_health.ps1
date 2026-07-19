# Watchdog za OSRM proxy + Tailscale Funnel.
#
# Problem koji ovo resava: start_osrm_server.ps1 se pokrece SAMO pri logon-u
# na Windows (Scheduled Task GavraOSRM_Autostart, "at logon" trigger). Ako
# python proxy proces (osrm_proxy.py) padne, ili Tailscale Funnel izgubi
# konekciju/rute, ETA i auto-tracking (10 min pre polaska) prestaju da rade
# do sledeceg logon-a - sto se u praksi retko desava na serverskoj masini.
#
# Ova skripta se poziva periodicno (npr. svakih 2 minuta) preko posebnog
# Scheduled Task-a (GavraOSRM_Watchdog, "repeat every N minutes" trigger,
# koji NE zavisi od logon-a) i:
#   1. Proveri lokalni OSRM health (http://127.0.0.1:5000/route/...)
#   2. Proveri da li port 8000 (osrm_proxy.py) slusa
#   3. Proveri javni health-check (Tailscale Funnel URL)
# Ako bilo koja provera ne uspe, ponovo pokrece start_osrm_server.ps1 koji
# idempotentno dize Docker kontejner, proxy i Tailscale funnel rute.

$ErrorActionPreference = "Continue"

$ServiceDir = "c:\Users\Bojan\gavra_android\osrm-service"
$LogFile = "$ServiceDir\osrm_watchdog.log"
$StartScript = "$ServiceDir\start_osrm_server.ps1"
# Root URL ne zahteva X-API-Key (osrm_proxy.py: read_root je izuzet od provere kljuca)
# - koristimo ga kao lagan health-check da potvrdimo da su proxy + Tailscale Funnel dostupni,
# bez potrebe da watchdog skripta cuva ML_API_KEY.
$PublicHealthUrl = "https://win-vfeglqf71ss.tail61b7a2.ts.net/"
$LocalHealthUrl = "http://127.0.0.1:5000/route/v1/driving/21.4243,44.9028;21.3011,45.1187?overview=false"

function Log($msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    Add-Content -Path $LogFile -Value $line
}

# Drzi log fajl razumne velicine (poslednjih ~2000 linija)
if (Test-Path $LogFile) {
    $content = Get-Content $LogFile -Tail 2000
    Set-Content -Path $LogFile -Value $content
}

$needsRestart = $false
$reasons = @()

# 1. Lokalni OSRM health-check
try {
    $localResp = Invoke-RestMethod -Uri $LocalHealthUrl -TimeoutSec 8
    if ($localResp.code -ne "Ok") {
        $needsRestart = $true
        $reasons += "lokalni OSRM vratio code=$($localResp.code)"
    }
} catch {
    $needsRestart = $true
    $reasons += "lokalni OSRM health-check nije uspeo: $($_.Exception.Message)"
}

# 2. Da li proxy port 8000 slusa
$proxyListening = Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue
if (-not $proxyListening) {
    $needsRestart = $true
    $reasons += "OSRM proxy (port 8000) ne slusa"
}

# 3. Javni (Tailscale Funnel) health-check - samo ako su prethodne provere OK,
#    da ne dupliramo restart razlog kad je lokalno vec pokvareno.
if (-not $needsRestart) {
    try {
        $publicResp = Invoke-RestMethod -Uri $PublicHealthUrl -TimeoutSec 12
        if ($publicResp.status -ne "active") {
            $needsRestart = $true
            $reasons += "javni (Funnel) health-check vratio status=$($publicResp.status)"
        }
    } catch {
        $needsRestart = $true
        $reasons += "javni (Funnel) health-check nije uspeo: $($_.Exception.Message)"
    }
}

if ($needsRestart) {
    Log "PROBLEM detektovan: $($reasons -join '; ') - pokrecem start_osrm_server.ps1 radi oporavka."
    try {
        & powershell.exe -ExecutionPolicy Bypass -File $StartScript *>> $LogFile
        Log "start_osrm_server.ps1 zavrsen (restart pokusaj)."
    } catch {
        Log "GRESKA pri pokretanju start_osrm_server.ps1: $($_.Exception.Message)"
    }
} else {
    Log "OK - lokalni OSRM, proxy port i javni Funnel health-check su svi ispravni."
}
