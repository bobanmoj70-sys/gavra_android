#Requires -Version 5.1
<#
.SYNOPSIS
  Uvek pokrece scrcpy na test telefonu sa razbijenim ekranom (Huawei NOH-NX9).

.DESCRIPTION
  Preferira wireless ADB (IP:5555). Ako je telefon na USB-u, jednom ukljuci tcpip
  pa se poveze preko Wi-Fi. Fallback na USB.

  Podrazumevano radi u watchdog rezimu: ako se scrcpy zatvori ili veza padne,
  sam se ponovo poveze i pokrene. Pri startu Windowsa ide preko Startup foldera.

.PARAMETER UsbOnly
  Forsira samo USB (ne pokusava wireless).

.PARAMETER WirelessOnly
  Samo wireless (ne koristi USB serial za scrcpy).

.PARAMETER InstallStartup
  Dodaje shortcut u Windows Startup folder (watchdog).

.PARAMETER UninstallStartup
  Uklanja Startup entry.

.PARAMETER Once
  Pokreni scrcpy samo jednom (bez auto-restart).

.PARAMETER RetrySeconds
  Pauza izmedju pokusaja kad scrcpy padne ili telefon nestane (default 5).
#>

[CmdletBinding()]
param(
    [switch]$UsbOnly,
    [switch]$WirelessOnly,
    [switch]$InstallStartup,
    [switch]$UninstallStartup,
    [switch]$Once,
    [int]$RetrySeconds = 5
)

$ErrorActionPreference = 'Stop'

# Fiksni test telefon (razbijen ekran)
$DeviceSerial = 'GBB0220B03001125'
$DeviceName  = 'HUAWEI NOH-NX9'
$AdbPort     = 5555
$StartupName = 'Gavra-Scrcpy-TestPhone.cmd'
$MutexName   = 'Global\GavraScrcpyTestPhone'

function Write-Info([string]$msg)  { Write-Host $msg -ForegroundColor Cyan }
function Write-Ok([string]$msg)    { Write-Host $msg -ForegroundColor Green }
function Write-Warn([string]$msg)  { Write-Host $msg -ForegroundColor Yellow }

function Get-StartupDir {
    return [Environment]::GetFolderPath('Startup')
}

function Install-StartupEntry {
    $startup = Get-StartupDir
    $cmdPath = Join-Path $startup $StartupName
    $scriptPath = $PSCommandPath
    $lines = @(
        '@echo off',
        'REM Auto-start + watchdog scrcpy za Gavra test telefon',
        'timeout /t 12 /nobreak >nul',
        ('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File "{0}"' -f $scriptPath)
    )
    Set-Content -Path $cmdPath -Value $lines -Encoding ASCII
    Write-Ok "Startup instaliran: $cmdPath"
    Write-Info 'Posle logina: scrcpy se pokrece i sam se vraca ako se zatvori/prekine.'
}

function Uninstall-StartupEntry {
    $cmdPath = Join-Path (Get-StartupDir) $StartupName
    if (Test-Path $cmdPath) {
        Remove-Item $cmdPath -Force
        Write-Ok "Startup uklonjen: $cmdPath"
    } else {
        Write-Warn 'Startup entry nije pronadjen.'
    }
}

function Find-Adb {
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
        "$env:USERPROFILE\AppData\Local\Android\Sdk\platform-tools\adb.exe"
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }
    throw 'adb nije u PATH-u. Instaliraj Android platform-tools.'
}

function Find-Scrcpy {
    $cmd = Get-Command scrcpy -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $wingetRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path $wingetRoot) {
        $found = Get-ChildItem -Path $wingetRoot -Filter 'scrcpy.exe' -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
        if ($found) { return $found }
    }
    throw 'scrcpy nije pronadjen. Instaliraj: winget install Genymobile.scrcpy'
}

function Get-AdbDevices([string]$adb) {
    $lines = @(& $adb devices 2>$null)
    foreach ($line in $lines) {
        if ($line -match '^(\S+)\s+(device|offline|unauthorized)\s*') {
            [pscustomobject]@{ Serial = $Matches[1]; State = $Matches[2] }
        }
    }
}

function Test-DeviceOnline([string]$adb, [string]$serial) {
    $d = @(Get-AdbDevices $adb | Where-Object { $_.Serial -eq $serial -and $_.State -eq 'device' })
    return $d.Count -gt 0
}

function Get-DeviceWifiIp([string]$adb, [string]$serial) {
    # Out-String: -match on arrays filters instead of setting $Matches -> "Cannot index into a null array"
    $route = (& $adb -s $serial shell ip route 2>$null | Out-String)
    if ($route -match 'src\s+(\d+\.\d+\.\d+\.\d+)') { return $Matches[1] }

    $wlan = (& $adb -s $serial shell ip -f inet addr show wlan0 2>$null | Out-String)
    if ($wlan -match 'inet\s+(\d+\.\d+\.\d+\.\d+)') { return $Matches[1] }

    $prop = (& $adb -s $serial shell getprop dhcp.wlan0.ipaddress 2>$null | Out-String).Trim()
    if ($prop -match '^\d+\.\d+\.\d+\.\d+$') { return $prop }

    return $null
}

function Connect-Wireless([string]$adb, [string]$usbSerial) {
    if (-not (Test-DeviceOnline $adb $usbSerial)) {
        Write-Warn "USB uredjaj $usbSerial nije online - wireless setup zahteva USB jednom."
        return $null
    }

    $ip = Get-DeviceWifiIp $adb $usbSerial
    if (-not $ip) {
        Write-Warn 'Ne mogu da procitam Wi-Fi IP. Telefon mora biti na istoj mrezi kao PC.'
        return $null
    }

    Write-Info "Wi-Fi IP: $ip - ukljucujem tcpip :$AdbPort ..."
    & $adb -s $usbSerial tcpip $AdbPort 2>$null | Out-Null
    Start-Sleep -Seconds 2

    $target = "${ip}:${AdbPort}"
    Write-Info "adb connect $target"
    $out = & $adb connect $target 2>&1 | Out-String
    Write-Host $out.Trim()
    Start-Sleep -Seconds 1

    if (Test-DeviceOnline $adb $target) {
        Write-Ok "Wireless OK: $target"
        return $target
    }

    Write-Warn 'Wireless connect nije uspeo (firewall / ista mreza?).'
    return $null
}

function Resolve-TargetSerial([string]$adb) {
    # 1) Vec postoji wireless sesija za ovaj telefon?
    $wireless = @(Get-AdbDevices $adb | Where-Object {
        $_.State -eq 'device' -and $_.Serial -match '^\d+\.\d+\.\d+\.\d+:\d+$'
    })
    foreach ($w in $wireless) {
        $sn = (& $adb -s $w.Serial shell getprop ro.serialno 2>$null | Out-String).Trim()
        if ($sn -eq $DeviceSerial -or [string]::IsNullOrWhiteSpace($sn)) {
            Write-Ok "Koristim postojeci wireless: $($w.Serial)"
            return $w.Serial
        }
    }

    if ($UsbOnly) {
        if (Test-DeviceOnline $adb $DeviceSerial) { return $DeviceSerial }
        throw "USB uredjaj $DeviceSerial nije povezan."
    }

    # 2) USB prisutan -> bootstrap wireless
    if (Test-DeviceOnline $adb $DeviceSerial) {
        $wl = Connect-Wireless $adb $DeviceSerial
        if ($wl) {
            Write-Info 'Mozes iskopcati USB kabl - scrcpy ide preko Wi-Fi.'
            return $wl
        }
        if (-not $WirelessOnly) {
            Write-Warn 'Wireless nije uspeo - nastavljam na USB.'
            return $DeviceSerial
        }
        throw 'WirelessOnly: connect nije uspeo.'
    }

    # 3) Nema USB - bilo koji wireless device
    $anyWl = @(Get-AdbDevices $adb | Where-Object {
        $_.State -eq 'device' -and $_.Serial -match '^\d+\.\d+\.\d+\.\d+:\d+$'
    }) | Select-Object -First 1
    if ($anyWl) {
        Write-Ok "Koristim wireless: $($anyWl.Serial)"
        return $anyWl.Serial
    }

    if ($WirelessOnly) {
        throw 'Wireless nije dostupan. Prikljuci USB jednom i pokreni skriptu da se upari IP:5555.'
    }

    if (Test-DeviceOnline $adb $DeviceSerial) {
        Write-Ok "Koristim USB: $DeviceSerial"
        return $DeviceSerial
    }

    throw "Telefon $DeviceName ($DeviceSerial) nije nadjen. Prikljuci USB ili omoguci wireless ADB."
}

function Prepare-Device([string]$adb, [string]$serial) {
    Write-Info 'Podesavam screen timeout na 30 min...'
    & $adb -s $serial shell settings put system screen_off_timeout 1800000 2>$null | Out-Null

    Write-Info 'Budim uredjaj...'
    & $adb -s $serial shell input keyevent 224 2>$null | Out-Null  # WAKEUP
    Start-Sleep -Milliseconds 400
    & $adb -s $serial shell input keyevent 82 2>$null | Out-Null   # MENU / unlock attempt
}

# --- main ---
if ($InstallStartup) {
    Install-StartupEntry
    exit 0
}
if ($UninstallStartup) {
    Uninstall-StartupEntry
    exit 0
}

# Jedna instanca watchdoga
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($false, $MutexName, [ref]$createdNew)
$hasHandle = $false
try {
    $hasHandle = $mutex.WaitOne(0)
} catch {
    $hasHandle = $false
}
if (-not $hasHandle) {
    Write-Warn 'Scrcpy launcher vec radi (druga instanca). Izlazim.'
    try { $mutex.Dispose() } catch {}
    exit 0
}

try {
    Write-Host ''
    Write-Host "=== Gavra scrcpy - $DeviceName ===" -ForegroundColor Magenta
    Write-Host "Serial: $DeviceSerial" -ForegroundColor DarkGray
    if ($Once) {
        Write-Host 'Mod: jednokratno (-Once)' -ForegroundColor DarkGray
    } else {
        Write-Host "Mod: watchdog (auto-restart, retry ${RetrySeconds}s)" -ForegroundColor DarkGray
        Write-Host 'Zatvori ovaj prozor ili Ctrl+C da zaustavis watchdog.' -ForegroundColor DarkGray
    }
    Write-Host ''

    $adb = Find-Adb
    $scrcpy = Find-Scrcpy
    Write-Info "adb:    $adb"
    Write-Info "scrcpy: $scrcpy"

    $attempt = 0
    while ($true) {
        $attempt++
        try {
            Write-Host ''
            Write-Info "Pokusaj #$attempt - uredjaji:"
            & $adb devices -l

            $target = Resolve-TargetSerial $adb
            Prepare-Device $adb $target

            Write-Ok "Pokrecem scrcpy na $target ..."
            Write-Host '  --stay-awake --show-touches' -ForegroundColor DarkGray
            Write-Host ''

            & $scrcpy `
                --serial $target `
                --stay-awake `
                --show-touches `
                --window-title "Gavra Test - $DeviceName"

            $code = $LASTEXITCODE
            if ($null -eq $code) { $code = 0 }
            Write-Warn "scrcpy zavrsen (exit $code)."
        }
        catch {
            Write-Warn "Greska: $($_.Exception.Message)"
        }

        if ($Once) {
            break
        }

        Write-Info "Cekam $RetrySeconds s pa ponovo pokrecam (telefon/USB/Wi-Fi)..."
        Start-Sleep -Seconds $RetrySeconds
    }
}
finally {
    try { $mutex.ReleaseMutex() } catch {}
    try { $mutex.Dispose() } catch {}
}
