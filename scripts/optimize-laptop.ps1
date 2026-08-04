# LAPTOP OPTIMIZATION SCRIPT
# Pokreni kao Administrator za sve funkcije

Write-Host "========================================"
Write-Host "   LAPTOP OPTIMIZATION SCRIPT"
Write-Host "========================================"
Write-Host ""

# Proveri da li je pokrenuto kao Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[!] Preporuka: Pokreni kao Administrator za sve funkcije" -ForegroundColor Yellow
}

# 1. Postavi High Performance power plan
Write-Host ""
Write-Host "[1/6] Podesavam High Performance power plan..."
powercfg -setactive SCHEME_MIN 2>$null
Write-Host "     High Performance aktiviran" -ForegroundColor Green

# 2. Ocisti TEMP foldere (starije od 7 dana)
Write-Host ""
Write-Host "[2/6] Cistim TEMP foldere..."
$deletedCount = 0
Get-ChildItem -Path $env:TEMP -Recurse -Force -ErrorAction SilentlyContinue | 
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | 
    ForEach-Object { 
        Remove-Item $_.FullName -Force -Recurse -ErrorAction SilentlyContinue
        $deletedCount++
    }
Write-Host "     Obrisano $deletedCount starih fajlova" -ForegroundColor Green

# 3. Top procesi po RAM
Write-Host ""
Write-Host "[3/6] Top 10 procesa po RAM potrosnji:"
Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 | ForEach-Object {
    $ramMB = [math]::Round($_.WorkingSet64 / 1MB, 0)
    $name = $_.ProcessName.PadRight(30)
    Write-Host "     $name - $ramMB MB"
}

# 4. Ocisti Windows Update cache (ako admin)
Write-Host ""
Write-Host "[4/6] Windows Update cache..."
if ($isAdmin) {
    Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
    Start-Service -Name wuauserv -ErrorAction SilentlyContinue
    Write-Host "     Ociscen" -ForegroundColor Green
} else {
    Write-Host "     Preskoceno - potreban Administrator" -ForegroundColor Yellow
}

# 5. Garbage collection
Write-Host ""
Write-Host "[5/6] Oslobadjam memoriju..."
[System.GC]::Collect()
Write-Host "     Zavrseno" -ForegroundColor Green

# 6. Prikazi stanje memorije
Write-Host ""
Write-Host "[6/6] Stanje memorije:"
$os = Get-CimInstance Win32_OperatingSystem
$totalRAM = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
$freeRAM = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
$usedRAM = [math]::Round($totalRAM - $freeRAM, 2)

Write-Host "     Ukupno:    $totalRAM GB"
Write-Host "     Koristeno: $usedRAM GB" -ForegroundColor Yellow
Write-Host "     Slobodno:  $freeRAM GB" -ForegroundColor Green

Write-Host ""
Write-Host "========================================"
Write-Host "   OPTIMIZACIJA ZAVRSENA!"
Write-Host "========================================"
Write-Host ""
Write-Host "SAVETI:"
Write-Host "1. Zatvori Chrome tabove koje ne koristis"
Write-Host "2. Zatvori nepotrebne VS Code prozore"
Write-Host "3. Restartuj laptop bar jednom nedeljno"
