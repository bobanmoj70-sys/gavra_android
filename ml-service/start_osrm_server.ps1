# Pokreće OSRM Docker kontejner (ako nije već pokrenut) i ponovo primenjuje
# Tailscale serve/funnel rute za javni pristup.
# Napomena: i / i /osrm idu na AI server (main.py, port 8000) - AI server ima
# ugrađen reverse proxy koji /osrm/* prosleđuje lokalnom OSRM kontejneru (port 5000).
# Poziva se automatski pri prijavi u Windows preko Scheduled Task-a
# (vidi setup_osrm_autostart.ps1), ili ručno kad je potrebno.

$ErrorActionPreference = "Continue"

$LogFile = "c:\Users\Bojan\gavra_android\ml-service\osrm_autostart.log"
$TailscaleExe = "C:\Program Files\Tailscale\tailscale.exe"
$DockerBin = "C:\Program Files\Docker\Docker\resources\bin"
$OsrmDataDir = "C:/osrm-data"
$ContainerName = "osrm-server"

function Log($msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

if (-not ($env:Path -like "*$DockerBin*")) {
    $env:Path += ";$DockerBin"
}

Log "=== Pokretanje OSRM autostart skripte ==="

# 1. Sačekaj da Docker Desktop engine bude spreman (do 3 minuta)
$maxWaitSeconds = 180
$waited = 0
$dockerReady = $false
while ($waited -lt $maxWaitSeconds) {
    docker ps > $null 2>&1
    if ($LASTEXITCODE -eq 0) {
        $dockerReady = $true
        break
    }
    if ($waited -eq 0) {
        Log "Docker engine nije spreman, pokušavam da pokrenem Docker Desktop..."
        Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe" -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 5
    $waited += 5
}

if (-not $dockerReady) {
    Log "GREŠKA: Docker engine se nije pokrenuo u roku od $maxWaitSeconds sekundi. Prekidam."
    exit 1
}

Log "Docker engine je spreman."

# 2. Proveri da li osrm-server kontejner postoji i radi
$containerStatus = docker inspect -f '{{.State.Running}}' $ContainerName 2>$null

if ($containerStatus -eq "true") {
    Log "Kontejner '$ContainerName' je već pokrenut."
} elseif ($containerStatus -eq "false") {
    Log "Kontejner '$ContainerName' postoji ali nije pokrenut. Pokrećem..."
    docker start $ContainerName | Out-Null
    Start-Sleep -Seconds 3
} else {
    Log "Kontejner '$ContainerName' ne postoji. Kreiram novi..."
    docker run -d --name $ContainerName --restart unless-stopped -p 5000:5000 `
        -v "${OsrmDataDir}:/data" osrm/osrm-backend osrm-routed --algorithm mld /data/region.osrm | Out-Null
    Start-Sleep -Seconds 3
}

# 3. Health-check OSRM lokalno (sa retry-om, jer osrm-routed treba par sekundi da učita mapu)
$osrmLocalOk = $false
for ($i = 1; $i -le 6; $i++) {
    try {
        $resp = Invoke-RestMethod -Uri "http://127.0.0.1:5000/route/v1/driving/21.4243,44.9028;21.3011,45.1187?overview=false" -TimeoutSec 10
        if ($resp.code -eq "Ok") {
            Log "OSRM health-check OK (lokalno)."
            $osrmLocalOk = $true
            break
        }
        Log "UPOZORENJE: OSRM health-check vratio code=$($resp.code) (pokušaj $i/6)"
    } catch {
        Log "OSRM health-check pokušaj $i/6 nije uspeo: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds 5
}
if (-not $osrmLocalOk) {
    Log "GREŠKA: OSRM lokalni health-check nije uspeo nakon 6 pokušaja."
}

# 4. Ponovo primeni Tailscale serve + funnel rute (idempotentno)
if (-not (Test-Path $TailscaleExe)) {
    Log "GREŠKA: Tailscale nije pronađen na $TailscaleExe"
    exit 1
}

try {
    & $TailscaleExe funnel --bg --set-path / http://127.0.0.1:8000 2>&1 | ForEach-Object { Log "  tailscale: $_" }
    & $TailscaleExe funnel --bg --set-path /osrm http://127.0.0.1:8000/osrm 2>&1 | ForEach-Object { Log "  tailscale: $_" }
    Log "Tailscale funnel rute ponovo primenjene."
} catch {
    Log "GREŠKA pri primeni Tailscale ruta: $($_.Exception.Message)"
}

# 5. Sačekaj da AI server (port 8000) bude gore pre javnog health-checka.
# Javni /osrm health-check zavisi od AI servera jer on radi proxy ka OSRM-u,
# a ovaj task i GavraAI_Server_Autostart se pokreću nezavisno pri logon-u.
$aiServerReady = $false
for ($i = 1; $i -le 12; $i++) {
    $conn = Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue
    if ($conn) {
        $aiServerReady = $true
        break
    }
    if ($i -eq 1) { Log "Čekam da AI server (port 8000) bude gore..." }
    Start-Sleep -Seconds 5
}
if ($aiServerReady) {
    Log "AI server (port 8000) je spreman."
} else {
    Log "UPOZORENJE: AI server (port 8000) nije otvorio port nakon 60s. Javni health-check će verovatno pući."
}

# 6. Health-check preko javnog Funnel URL-a
try {
    $publicResp = Invoke-RestMethod -Uri "https://win-vfeglqf71ss.tail61b7a2.ts.net/osrm/route/v1/driving/21.4243,44.9028;21.3011,45.1187?overview=false" -TimeoutSec 15
    if ($publicResp.code -eq "Ok") {
        Log "OSRM javni (Funnel) health-check OK."
    } else {
        Log "UPOZORENJE: Javni health-check vratio code=$($publicResp.code)"
    }
} catch {
    Log "UPOZORENJE: Javni health-check nije uspeo (možda Funnel treba par sekundi da se aktivira): $($_.Exception.Message)"
}

Log "=== OSRM autostart skripta završena ==="
