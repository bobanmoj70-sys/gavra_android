# Gavra AI Server - dijagnosticka skripta
# Pokreni na laptopu koji sluzi kao AI server
# Ne menja nista, samo prikuplja informacije i pravi izvestaj

$ErrorActionPreference = "SilentlyContinue"

$ProjectRoot = 'c:\Users\Bojan\gavra_android'
$ServiceDir = Join-Path $ProjectRoot 'ml-service'
$ReportFile = Join-Path $ServiceDir 'diagnose_ai_report.txt'
$Port = 8000

function Write-ReportLine {
    param([string]$Line, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $prefix = switch ($Level) {
        'OK'    { '[OK]   ' }
        'WARN'  { '[UPOZORENJE] ' }
        'ERROR' { '[GRESKA] ' }
        default { '[INFO] ' }
    }
    $output = "$timestamp $prefix$Line"
    Write-Host $output
    Add-Content -Path $ReportFile -Value $output -Encoding UTF8
}

function Test-CommandExists {
    param([string]$Command)
    return [bool](Get-Command $Command -ErrorAction SilentlyContinue)
}

function Get-ProcessRamMB {
    param([string]$NamePattern)
    $procs = Get-Process | Where-Object { $_.ProcessName -like $NamePattern }
    if (-not $procs) { return 0 }
    $total = ($procs | Measure-Object WorkingSet64 -Sum).Sum
    return [math]::Round($total / 1MB, 1)
}

function Test-HttpEndpoint {
    param([string]$Url, [int]$TimeoutSec = 5)
    try {
        $resp = Invoke-WebRequest -Uri $Url -Method GET -TimeoutSec $TimeoutSec -UseBasicParsing
        return @{ Success = $true; StatusCode = $resp.StatusCode; Body = $resp.Content }
    } catch {
        return @{ Success = $false; StatusCode = $_.Exception.Response.StatusCode.Value__; Body = $_.Exception.Message }
    }
}

# Obrisi stari izvestaj
if (Test-Path $ReportFile) {
    Remove-Item $ReportFile -Force
}

Write-ReportLine "=== Gavra AI Server dijagnostika ===" 'INFO'
Write-ReportLine "Pokrenuto na: $env:COMPUTERNAME" 'INFO'
Write-ReportLine ""

# 1. OSNOVNE INFORMACIJE O SISTEMU
Write-ReportLine "--- Sistem i RAM ---" 'INFO'
try {
    $os = Get-CimInstance Win32_OperatingSystem
    $totalRamMB = [math]::Round($os.TotalVisibleMemorySize / 1024, 0)
    $freeRamMB = [math]::Round($os.FreePhysicalMemory / 1024, 0)
    $usedRamMB = $totalRamMB - $freeRamMB
    $ramPercent = [math]::Round(($usedRamMB / $totalRamMB) * 100, 1)

    Write-ReportLine "Ukupno RAM: $totalRamMB MB ($([math]::Round($totalRamMB/1024, 1)) GB)" 'INFO'
    Write-ReportLine "Slobodno RAM: $freeRamMB MB ($([math]::Round($freeRamMB/1024, 1)) GB)" 'INFO'
    Write-ReportLine "Zauzeto RAM: $usedRamMB MB ($ramPercent%)" 'INFO'

    if ($freeRamMB -lt 1024) {
        Write-ReportLine "Slobodno RAM-a je ispod 1 GB. Ovo moze uzrokovati probleme sa ucitavanjem AI modela." 'ERROR'
    } elseif ($freeRamMB -lt 3072) {
        Write-ReportLine "Slobodno RAM-a je ispod 3 GB. Server moze raditi, ali ce biti tesko ako ima jos programa otvorenih." 'WARN'
    } else {
        Write-ReportLine "RAM izgleda dovoljan za rad AI servera." 'OK'
    }
} catch {
    Write-ReportLine "Nije moguce procitati RAM informacije: $_" 'ERROR'
}

# 2. GEMINI API I ENV PROVERA
Write-ReportLine "" 'INFO'
Write-ReportLine "--- Gemini API i environment provera ---" 'INFO'

$geminiApiKey = $env:GEMINI_API_KEY
if ($geminiApiKey -and $geminiApiKey.Length -gt 10) {
    Write-ReportLine "GEMINI_API_KEY je podesen." 'OK'
} else {
    Write-ReportLine "GEMINI_API_KEY nije podesen u environmentu. Proveri .env fajl." 'ERROR'
}

$mlApiKey = $env:ML_API_KEY
if ($mlApiKey -and $mlApiKey.Length -gt 10) {
    Write-ReportLine "ML_API_KEY je podesen." 'OK'
} else {
    Write-ReportLine "ML_API_KEY nije podesen u environmentu. Proveri .env fajl." 'WARN'
}

# Provera da li .env fajl postoji
$envFile = Join-Path $ServiceDir '.env'
if (Test-Path $envFile) {
    Write-ReportLine ".env fajl postoji u $ServiceDir" 'OK'
} else {
    Write-ReportLine ".env fajl ne postoji u $ServiceDir. Kopiraj .env.example u .env i popuni ga." 'ERROR'
}

# 3. AI SERVER PROVERA
Write-ReportLine "" 'INFO'
Write-ReportLine "--- Gavra AI Server provera ---" 'INFO'

$pythonRam = Get-ProcessRamMB '*python*'
if ($pythonRam -gt 0) {
    Write-ReportLine "Python procesi su aktivni. RAM potrosnja: $pythonRam MB" 'INFO'
} else {
    Write-ReportLine "Nema aktivnih Python procesa." 'WARN'
}

$serverConn = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
if ($serverConn) {
    try {
        $proc = Get-Process -Id $serverConn.OwningProcess -ErrorAction SilentlyContinue
        Write-ReportLine "Port $Port je zauzet. Proces: $($proc.ProcessName) (PID: $($proc.Id))" 'OK'
    } catch {
        Write-ReportLine "Port $Port je zauzet, ali nije moguce identifikovati proces." 'WARN'
    }

    $serverHealth = Test-HttpEndpoint "http://localhost:$Port" 5
    if ($serverHealth.Success) {
        Write-ReportLine "AI server odgovara na http://localhost:$Port (status: $($serverHealth.StatusCode))" 'OK'
        Write-ReportLine "Odgovor: $($serverHealth.Body)" 'INFO'
    } else {
        Write-ReportLine "Port $Port je zauzet, ali AI server NE odgovara ispravno." 'ERROR'
    }
} else {
    Write-ReportLine "Port $Port nije zauzet. AI server nije pokrenut." 'ERROR'
}

# 4. LOGOVI
Write-ReportLine "" 'INFO'
Write-ReportLine "--- Poslednji logovi ---" 'INFO'

$logFiles = @(
    (Join-Path $ServiceDir 'gavra_ai.log'),
    (Join-Path $ServiceDir 'server_watchdog.log')
)

foreach ($logFile in $logFiles) {
    if (Test-Path $logFile) {
        Write-ReportLine "Log fajl: $logFile" 'INFO'
        try {
            $lines = Get-Content $logFile -Tail 20 -Encoding UTF8
            $lines | ForEach-Object { Write-ReportLine "  $_" 'INFO' }
        } catch {
            Write-ReportLine "  Nije moguce procitati log: $_" 'WARN'
        }
    } else {
        Write-ReportLine "Log fajl ne postoji: $logFile" 'WARN'
    }
    Write-ReportLine "" 'INFO'
}

# 5. MREZA
Write-ReportLine "--- Mreza ---" 'INFO'

try {
    $tailscale = Get-Process -Name 'tailscale-ipn' -ErrorAction SilentlyContinue
    if ($tailscale) {
        Write-ReportLine "Tailscale je pokrenut." 'OK'
    } else {
        Write-ReportLine "Tailscale nije pokrenut. Ako koristis pristup van kuce, proveri Tailscale." 'WARN'
    }
} catch {
    Write-ReportLine "Nije moguce proveriti Tailscale: $_" 'WARN'
}

try {
    $localIp = (Get-NetIPAddress -AddressFamily IPv4 -PrefixOrigin Dhcp -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress
    if ($localIp) {
        Write-ReportLine "Lokalna IP adresa laptopa: $localIp" 'INFO'
    }
} catch {
    Write-ReportLine "Nije moguce procitati lokalnu IP adresu." 'WARN'
}

# 6. ZAKLJUCAK
Write-ReportLine "" 'INFO'
Write-ReportLine "=== Zakljucak ===" 'INFO'

$reportContent = Get-Content $ReportFile -Raw
if ($reportContent -match '\[GRESKA\]') {
    Write-ReportLine "Postoje GRESKE koje sprecavaju ispravan rad AI servera." 'ERROR'
    Write-ReportLine "Resi najpre stavke oznacene sa [GRESKA], zatim ponovo pokreni dijagnostiku." 'INFO'
} elseif ($reportContent -match '\[UPOZORENJE\]') {
    Write-ReportLine "Sistem radi, ali postoje UPOZORENJA koja mogu uzrokovati probleme." 'WARN'
    Write-ReportLine "Razmotri stavke oznacene sa [UPOZORENJE] za bolju stabilnost." 'INFO'
} else {
    Write-ReportLine "Sve izgleda ispravno. Gemini AI server bi trebalo da radi." 'OK'
}

Write-ReportLine "" 'INFO'
Write-ReportLine "Izvestaj sacuvan u: $ReportFile" 'INFO'
Write-Host ""
Write-Host "Izvestaj sacuvan u: $ReportFile" -ForegroundColor Cyan
