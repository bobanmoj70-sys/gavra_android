# Gavra AI Server - pouzdani startup skript sa watchdog-om
# Ova skripta pokreće ml-service i automatski ga restartuje ako padne.

$ErrorActionPreference = "Stop"

# --- ZAŠTITA OD DVOSTRUKOG POKRETANJA ---
# Ako se skripta pokrene dva puta (ručno + autostart), druga instanca odmah izlazi.
$MutexName = "Global\GavraAI_Server_Watchdog_Mutex"
$script:Mutex = $null
try {
    $script:Mutex = [System.Threading.Mutex]::OpenExisting($MutexName)
    Write-Host "[Gavra AI] Watchdog je već aktivan. Izlazim."
    exit 0
} catch {
    $script:Mutex = New-Object System.Threading.Mutex($false, $MutexName)
}
if (-not $script:Mutex.WaitOne(0, $false)) {
    Write-Host "[Gavra AI] Watchdog je već aktivan. Izlazim."
    exit 0
}

# Putanje
$ProjectRoot = 'c:\Users\Bojan\gavra_android'
$ServiceDir = Join-Path $ProjectRoot 'ml-service'
$LogDir = $ServiceDir
$LogFile = Join-Path $LogDir 'server_watchdog.log'
$PidFile = Join-Path $ServiceDir 'server.pid'
$Port = 8000
$MaxRestarts = 10
$RestartDelaySeconds = 5

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
}

function Test-ServerRunning {
    $conn = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
    if ($null -eq $conn) {
        return $false
    }
    # Proveri da li je to zaista naš python proces
    try {
        $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
        if ($proc -and ($proc.ProcessName -like "*python*")) {
            return $true
        }
    } catch {}
    return $false
}

function Stop-ExistingServer {
    # Zaustavi proces sa PID fajla ako postoji
    if (Test-Path $PidFile) {
        try {
            $oldPid = [int](Get-Content $PidFile -Raw).Trim()
            $proc = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
            if ($proc -and ($proc.ProcessName -like "*python*")) {
                Write-Log "Zaustavljam postojeći Python server iz PID fajla (PID: $oldPid)..."
                Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            }
            Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
        } catch {}
    }

    # Zaustavi bilo koji proces na portu
    $conn = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
    if ($conn) {
        try {
            $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
            if ($proc -and ($proc.ProcessName -like "*python*")) {
                Write-Log "Zaustavljam postojeći Python server na portu (PID: $($proc.Id))..."
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            }
        } catch {
            # Ako Stop-Process ne radi zbog prava pristupa, probaj taskkill
            try {
                $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
                if ($proc -and ($proc.ProcessName -like "*python*")) {
                    Write-Log "Pokušavam taskkill za PID: $($proc.Id)..."
                    Start-Process -FilePath 'taskkill.exe' -ArgumentList "/F /PID $($proc.Id)" -Wait -NoNewWindow -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 2
                }
            } catch {}
        }
    }
}

# Kreiraj log direktorijum ako ne postoji
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

Write-Log "=== Gavra AI Server watchdog pokrenut ==="

# Provera da li je server već pokrenut
if (Test-ServerRunning) {
    Write-Log "Server je već pokrenut na portu $Port. Zaustavljam ga i pokrećem ponovo..."
    Stop-ExistingServer
}

Set-Location -Path $ServiceDir

$restartCount = 0
$normalShutdown = $false
while ($restartCount -lt $MaxRestarts) {
    $restartCount++
    Write-Log "Pokretanje servera (pokušaj $restartCount od $MaxRestarts)..."

    try {
        # Proveri ponovo da niko nije zauzeo port
        if (Test-ServerRunning) {
            Write-Log "Port $Port je i dalje zauzet. Pokušavam da oslobodim..."
            Stop-ExistingServer
        }

        # Pokreni server
        $process = Start-Process -FilePath "python" -ArgumentList "main.py" -WorkingDirectory $ServiceDir -NoNewWindow -PassThru
        $process.Id | Set-Content -Path $PidFile -Encoding UTF8 -Force

        # Sačekaj da server otvori port
        $waited = 0
        while (-not (Test-ServerRunning) -and $waited -lt 120) {
            Start-Sleep -Seconds 1
            $waited++
            if ($process.HasExited) {
                Write-Log "Server proces se završio pre nego što je otvorio port."
                break
            }
        }

        if (Test-ServerRunning) {
            Write-Log "Server uspešno pokrenut na portu $Port (PID: $($process.Id))."
        } else {
            Write-Log "Server nije otvorio port $Port nakon 120 sekundi."
        }

        # Čekaj da se proces završi
        $process.WaitForExit()

        $exitCode = $process.ExitCode
        Write-Log "Server se zaustavio sa exit kodom $exitCode."

        if ($exitCode -eq 0) {
            Write-Log "Normalno gašenje servera. Prekidam watchdog."
            $normalShutdown = $true
            break
        }
    } catch {
        Write-Log "Greška tokom pokretanja servera: $_"
    }

    if ($restartCount -lt $MaxRestarts) {
        Write-Log "Ponovni pokušaj za $RestartDelaySeconds sekundi..."
        Start-Sleep -Seconds $RestartDelaySeconds
    } else {
        Write-Log "Dostignut maksimalan broj ponovnih pokušaja. Server se neće više restartovati."
    }
}

# Očisti PID fajl
if (Test-Path $PidFile) {
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
}

# Oslobodi mutex da bi buduće instance mogle da se pokrenu
if ($script:Mutex) {
    try { $script:Mutex.ReleaseMutex() } catch {}
    try { $script:Mutex.Dispose() } catch {}
}

if ($normalShutdown) {
    Write-Log "=== Gavra AI Server watchdog završio (normalno gašenje) ==="
} else {
    Write-Log "=== Gavra AI Server watchdog završio (greška) ==="
}
