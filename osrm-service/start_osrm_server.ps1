# Pokreće OSRM Docker kontejner (ako nije već pokrenut), pokreće ČIST OSRM
# reverse proxy (osrm_proxy.py, port 8000, BEZ ikakve AI/ML logike), i ponovo
# primenjuje Tailscale serve/funnel rute za javni pristup.
#
# VAŽNO: Ovo NAMERNO više ne zavisi od "AI servera" — stari main.py je
# kombinovao OSRM proxy sa neuronskom mrežom u istom procesu, što je značilo
# da je ETA/rutiranje za vozače prestajalo da radi ako je AI kod pukao ili bio
# ugašen. Sada je OSRM proxy potpuno samostalan proces.
#
# Poziva se automatski pri prijavi u Windows preko Scheduled Task-a
# (GavraOSRM_Autostart), ili ručno kad je potrebno.

$ErrorActionPreference = "Continue"

$ServiceDir = "c:\Users\Bojan\gavra_android\osrm-service"
$LogFile = "$ServiceDir\osrm_autostart.log"
$ProxyLogFile = "$ServiceDir\osrm_proxy.log"
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

Log "=== Pokretanje OSRM autostart skripte (samostalan proxy, bez AI) ==="

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

# 4. Pokreni ČIST OSRM proxy (osrm_proxy.py) na portu 8000, ako već nije gore
$proxyRunning = Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue
if ($proxyRunning) {
    Log "OSRM proxy (port 8000) je već pokrenut."
} else {
    Log "Pokrećem OSRM proxy (osrm_proxy.py) na portu 8000..."
    Start-Process -FilePath "python" `
        -ArgumentList "-m", "uvicorn", "osrm_proxy:app", "--host", "0.0.0.0", "--port", "8000" `
        -WorkingDirectory $ServiceDir `
        -WindowStyle Hidden `
        -RedirectStandardOutput $ProxyLogFile `
        -RedirectStandardError "$ServiceDir\osrm_proxy_err.log"

    $proxyReady = $false
    for ($i = 1; $i -le 12; $i++) {
        Start-Sleep -Seconds 5
        $conn = Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue
        if ($conn) { $proxyReady = $true; break }
    }
    if ($proxyReady) {
        Log "OSRM proxy (port 8000) je spreman."
    } else {
        Log "GREŠKA: OSRM proxy nije otvorio port 8000 u roku od 60s."
    }
}

# 5. Ponovo primeni Tailscale serve + funnel rute (idempotentno)
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
