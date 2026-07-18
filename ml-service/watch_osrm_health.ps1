# Periodicni health-check za OSRM kontejner.
# Za razliku od start_osrm_server.ps1 (koji se pokrece samo jednom, pri logon-u),
# ova skripta se poziva ponavljano (vidi setup_osrm_autostart.ps1 -> GavraOSRM_Watchdog task)
# i proverava da OSRM STVARNO odgovara na rute (ne samo da je Docker status "running").
# Ako lokalni health-check ne uspe, restartuje kontejner.

$ErrorActionPreference = "Continue"

$LogFile = "c:\Users\Bojan\gavra_android\ml-service\osrm_autostart.log"
$DockerBin = "C:\Program Files\Docker\Docker\resources\bin"
$ContainerName = "osrm-server"

function Log($msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [watchdog] $msg"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

if (-not ($env:Path -like "*$DockerBin*")) {
    $env:Path += ";$DockerBin"
}

# Preskoci ako Docker engine trenutno nije dostupan (npr. Docker Desktop se gasi/restartuje)
docker ps > $null 2>&1
if ($LASTEXITCODE -ne 0) {
    Log "Docker engine nije dostupan, preskacem ovaj ciklus provere."
    exit 0
}

$healthy = $false
try {
    $resp = Invoke-RestMethod -Uri "http://127.0.0.1:5000/route/v1/driving/21.4243,44.9028;21.3011,45.1187?overview=false" -TimeoutSec 8
    if ($resp.code -eq "Ok") {
        $healthy = $true
    }
} catch {
    # ignorisano, tretira se kao unhealthy ispod
}

if ($healthy) {
    # Sve OK, tiho izadji (nema potrebe da se svaki uspesan ciklus loguje i zatrpava log fajl)
    exit 0
}

Log "OSRM lokalni health-check nije uspeo. Proveravam status kontejnera '$ContainerName'..."

$containerStatus = docker inspect -f '{{.State.Running}}' $ContainerName 2>$null

if ($containerStatus -eq "true") {
    Log "Kontejner je 'running' ali ne odgovara na rute -> restartujem kontejner."
    docker restart $ContainerName | Out-Null
} elseif ($containerStatus -eq "false") {
    Log "Kontejner postoji ali nije pokrenut -> pokrecem."
    docker start $ContainerName | Out-Null
} else {
    Log "Kontejner '$ContainerName' ne postoji. Watchdog ga ne kreira (to radi start_osrm_server.ps1) - pokretanje preskoceno."
    exit 1
}

Start-Sleep -Seconds 5

try {
    $resp2 = Invoke-RestMethod -Uri "http://127.0.0.1:5000/route/v1/driving/21.4243,44.9028;21.3011,45.1187?overview=false" -TimeoutSec 8
    if ($resp2.code -eq "Ok") {
        Log "OSRM je ponovo zdrav nakon restarta."
    } else {
        Log "UPOZORENJE: OSRM i dalje ne odgovara ispravno nakon restarta (code=$($resp2.code))."
    }
} catch {
    Log "GRESKA: OSRM i dalje ne odgovara ni nakon restarta: $($_.Exception.Message)"
}
