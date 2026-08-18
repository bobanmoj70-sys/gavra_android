# Periodična provera OSRM + Tailscale Funnel javnog DNS-a.
# Supabase Edge ne vidi MagicDNS (100.x) — hostname MORA da postoji na 8.8.8.8.
#
# Registruje se kao Scheduled Task GavraOSRM_Watchdog (svaka 3 min).
# Ne dira ništa ako je sve zdravo.

$ErrorActionPreference = "Continue"

$ServiceDir = $PSScriptRoot
$LogFile = "$ServiceDir\osrm_watchdog.log"
$TailscaleExe = "C:\Program Files\Tailscale\tailscale.exe"
$StartScript = Join-Path $ServiceDir "start_osrm_server.ps1"
$FunnelHost = "win-vfeglqf71ss.tail61b7a2.ts.net"
$MutexName = "Global\GavraOSRMService"

function Log($msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

function Rotate-LogIfNeeded {
    if ((Test-Path $LogFile) -and ((Get-Item $LogFile).Length -gt 1MB)) {
        $bak = "$LogFile.bak"
        if (Test-Path $bak) { Remove-Item $bak -Force -ErrorAction SilentlyContinue }
        Move-Item $LogFile $bak -Force -ErrorAction SilentlyContinue
    }
}

function Test-LocalOsrm {
    try {
        $resp = Invoke-RestMethod -Uri "http://127.0.0.1:5000/route/v1/driving/21.4243,44.9028;21.3011,45.1187?overview=false" -TimeoutSec 5
        return $resp.code -eq "Ok"
    } catch {
        return $false
    }
}

function Test-ProxyPort {
    return [bool](Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue)
}

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

function Enable-Funnel {
    if (-not (Test-Path $TailscaleExe)) {
        Log "GREŠKA: Tailscale nije pronađen."
        return
    }
    & $TailscaleExe funnel --bg --set-path / http://127.0.0.1:8000 2>&1 | ForEach-Object { Log "  tailscale: $_" }
}

function Recycle-Funnel {
    if (-not (Test-Path $TailscaleExe)) {
        Log "GREŠKA: Tailscale nije pronađen."
        return
    }
    Log "Recikliram Tailscale Funnel..."
    & $TailscaleExe funnel --https=443 off 2>&1 | ForEach-Object { Log "  tailscale: $_" }
    Start-Sleep -Seconds 3
    Enable-Funnel
    Start-Sleep -Seconds 8
}

function Invoke-FullStart {
    if (-not (Test-Path $StartScript)) {
        Log "GREŠKA: Nedostaje $StartScript"
        return
    }
    if ($script:taken) {
        $mutex.ReleaseMutex() | Out-Null
        $script:taken = $false
    }
    Log "Pokrećem full start_osrm_server.ps1..."
    & powershell.exe -ExecutionPolicy Bypass -File $StartScript
}

Rotate-LogIfNeeded

if (-not $env:GAVRA013_API_KEY) {
    $env:GAVRA013_API_KEY = [Environment]::GetEnvironmentVariable("GAVRA013_API_KEY", "User")
}
if (-not $env:GAVRA013_API_KEY) {
    Log "GREŠKA: GAVRA013_API_KEY nije definisan. Watchdog prekida."
    exit 1
}

$mutex = New-Object System.Threading.Mutex($false, $MutexName)
$taken = $false
try {
    $taken = $mutex.WaitOne(0)
    $script:taken = $taken
    if (-not $taken) {
        exit 0
    }

    $osrmOk = Test-LocalOsrm
    $proxyOk = Test-ProxyPort
    $dnsOk = Test-FunnelPublicDns -HostName $FunnelHost

    if ($osrmOk -and $proxyOk -and $dnsOk) {
        $now = Get-Date
        $lastOkStamp = Join-Path $ServiceDir ".osrm_watchdog_ok"
        $shouldLogOk = $true
        if (Test-Path $lastOkStamp) {
            $prev = Get-Item $lastOkStamp
            if (($now - $prev.LastWriteTime).TotalMinutes -lt 30) {
                $shouldLogOk = $false
            }
        }
        if ($shouldLogOk) {
            Log "OK: OSRM + proxy + javni DNS ($FunnelHost)"
            Set-Content -Path $lastOkStamp -Value $now.ToString("o")
        }
        exit 0
    }

    if (-not $osrmOk -or -not $proxyOk) {
        Log "PROBLEM: osrm=$osrmOk proxy=$proxyOk dns=$dnsOk"
        Invoke-FullStart
        exit 0
    }

    Log "PROBLEM: javni DNS za $FunnelHost nije vidljiv na 8.8.8.8 (osrm=OK proxy=OK)"
    Recycle-Funnel
    if (Test-FunnelPublicDns -HostName $FunnelHost) {
        Log "Funnel javni DNS je ponovo objavljen."
    } else {
        Log "DNS i dalje NXDOMAIN posle recycle. Radim full start."
        Invoke-FullStart
    }
} finally {
    if ($script:taken) { $mutex.ReleaseMutex() | Out-Null }
    $mutex.Dispose()
}
