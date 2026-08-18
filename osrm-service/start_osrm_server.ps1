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
# (GavraOSRM_Autostart). GavraOSRM_Watchdog svaka 3 min proverava javni DNS
# i reciklira Funnel ako ime nestane sa 8.8.8.8.

$ErrorActionPreference = "Continue"

$ServiceDir = $PSScriptRoot
$LogFile = "$ServiceDir\osrm_autostart.log"
$ProxyLogFile = "$ServiceDir\osrm_proxy.log"
$TailscaleExe = "C:\Program Files\Tailscale\tailscale.exe"
$DockerBin = "C:\Program Files\Docker\Docker\resources\bin"
$OsrmDataDir = "C:/osrm-data"
$ContainerName = "osrm-server"
$MutexName = "Global\GavraOSRMService"

function Log($msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

$mutex = New-Object System.Threading.Mutex($false, $MutexName)
$taken = $false
try {
    $taken = $mutex.WaitOne(0)
    if (-not $taken) {
        Log "Drugi OSRM start/watchdog već radi, izlazim."
        exit 0
    }
} catch {
    Log "UPOZORENJE: mutex nije uspeo ($($_.Exception.Message)), nastavljam."
}

# Proveri neophodne environment varijable pre pokretanja
$apiKey = $env:GAVRA013_API_KEY
if (-not $apiKey) {
    $apiKey = [Environment]::GetEnvironmentVariable("GAVRA013_API_KEY", "User")
    $env:GAVRA013_API_KEY = $apiKey
}
if (-not $apiKey) {
    Log "GREŠKA: GAVRA013_API_KEY environment varijabla nije definisana. OSRM proxy zahteva API ključ."
    if ($taken) { $mutex.ReleaseMutex() | Out-Null }
    exit 1
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
    if ($taken) { $mutex.ReleaseMutex() | Out-Null }
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
    if ($taken) { $mutex.ReleaseMutex() | Out-Null }
    exit 1
}

$FunnelHost = "win-vfeglqf71ss.tail61b7a2.ts.net"

function Test-FunnelPublicDns {
    param([string]$HostName)
    $output = nslookup $HostName 8.8.8.8 2>&1 | Out-String
    if ($output -match "Non-existent domain|NXDOMAIN|can't find") {
        return $false
    }
    $ips = [regex]::Matches($output, '\b(?:\d{1,3}\.){3}\d{1,3}\b') | ForEach-Object { $_.Value } | Select-Object -Unique
    foreach ($ip in $ips) {
        if ($ip -eq "8.8.8.8") { continue }
        if ($ip -match '^100\.') { continue }
        if ($ip -match '^127\.') { continue }
        return $true
    }
    return $false
}

try {
    # Napomena: samo "/" ruta je potrebna — FastAPI app (osrm_proxy.py) sam
    # interno rutira /osrm/{path} ka lokalnom OSRM kontejneru, pa je poseban
    # /osrm Funnel unos redundantan i uklonjen je.
    & $TailscaleExe funnel --bg --set-path / http://127.0.0.1:8000 2>&1 | ForEach-Object { Log "  tailscale: $_" }
    Log "Tailscale funnel rute ponovo primenjene."
} catch {
    Log "GREŠKA pri primeni Tailscale ruta: $($_.Exception.Message)"
}

# Funnel može da javi "on" dok javni DNS još uvek vraća NXDOMAIN.
# Supabase Edge koristi javni DNS, ne Tailscale MagicDNS.
if (-not (Test-FunnelPublicDns -HostName $FunnelHost)) {
    Log "UPOZORENJE: Javni DNS za $FunnelHost je NXDOMAIN. Recikliram Funnel..."
    & $TailscaleExe funnel --https=443 off 2>&1 | ForEach-Object { Log "  tailscale: $_" }
    Start-Sleep -Seconds 3
    & $TailscaleExe funnel --bg --set-path / http://127.0.0.1:8000 2>&1 | ForEach-Object { Log "  tailscale: $_" }
    Start-Sleep -Seconds 8
    if (Test-FunnelPublicDns -HostName $FunnelHost) {
        Log "Javni DNS za $FunnelHost je ponovo objavljen."
    } else {
        Log "GREŠKA: Javni DNS za $FunnelHost i dalje ne postoji (8.8.8.8 NXDOMAIN). ETA iz Supabase Edge neće raditi."
    }
} else {
    Log "Javni DNS za $FunnelHost je OK (8.8.8.8)."
}

# 6. Health-check preko javnog Funnel URL-a
# Ovo sa ove mašine može ići preko MagicDNS (100.x) — zato DNS proveru radimo odvojeno.
try {
    $publicResp = Invoke-RestMethod -Uri "https://$FunnelHost/osrm/route/v1/driving/21.4243,44.9028;21.3011,45.1187?overview=false" -TimeoutSec 15 -Headers @{ "X-API-Key" = $apiKey }
    if ($publicResp.code -eq "Ok") {
        Log "OSRM Funnel HTTP health-check OK."
    } else {
        Log "UPOZORENJE: Funnel HTTP health-check vratio code=$($publicResp.code)"
    }
} catch {
    Log "UPOZORENJE: Funnel HTTP health-check nije uspeo: $($_.Exception.Message)"
}

Log "=== OSRM autostart skripta završena ==="

if ($taken) { $mutex.ReleaseMutex() | Out-Null }
