#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not (Test-Path (Join-Path $Root 'pubspec.yaml'))) {
  $Root = (Get-Location).Path
}
Set-Location $Root

$Master = Join-Path $Root 'assets\branding\gavra_icon.png'
if (-not (Test-Path $Master)) {
  throw "MISSING master icon: $Master - restore from git or place original black+blue 512px PNG here."
}

Add-Type -AssemblyName System.Drawing
$bmp = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Master).Path)
try {
  $w = $bmp.Width
  $h = $bmp.Height
  $corner = $bmp.GetPixel(0, 0)
  $letter = $bmp.GetPixel([int]($w * 0.2), [int]($h / 2))
  $okBlack = ($corner.A -ge 250) -and ($corner.R -le 8) -and ($corner.G -le 8) -and ($corner.B -le 8)
  $okBlue = ($letter.A -ge 200) -and ($letter.B -gt $letter.R) -and ($letter.B -gt 150)
  if (-not $okBlack) {
    throw "Master icon corner is not opaque black (A$($corner.A) R$($corner.R) G$($corner.G) B$($corner.B)). Refusing to sync."
  }
  if (-not $okBlue) {
    Write-Warning "Master letter sample may not be blue (A$($letter.A) R$($letter.R) G$($letter.G) B$($letter.B)). Continuing..."
  }
  Write-Host "OK master ${w}x${h} black+blue validated: $Master"
}
finally {
  $bmp.Dispose()
}

# Remove legacy aliases if present (single source of truth only)
$legacy = @(
  'assets\ic_launcher_512.png',
  'assets\logo_original.png',
  'assets\logo_transparent.png',
  'assets\logo_gavra.jpg'
)
foreach ($rel in $legacy) {
  $p = Join-Path $Root $rel
  if (Test-Path $p) {
    Remove-Item -Force $p
    Write-Host "Removed legacy: $rel"
  }
}

Write-Host "Running flutter_launcher_icons..."
& dart run flutter_launcher_icons
if ($LASTEXITCODE -ne 0) {
  throw "flutter_launcher_icons failed with exit $LASTEXITCODE"
}

# Splash / launch_background needs a real PNG bitmap (not adaptive XML)
$splashFg = Join-Path $Root 'android\app\src\main\res\drawable\ic_launcher_foreground.png'
Copy-Item -Force $Master $splashFg
Write-Host "Synced splash bitmap: android/app/src/main/res/drawable/ic_launcher_foreground.png"

$densities = @('mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi')
foreach ($d in $densities) {
  $src = Join-Path $Root "android\app\src\main\res\mipmap-$d\ic_launcher.png"
  $dst = Join-Path $Root "android\app\src\main\res\mipmap-$d\ic_launcher_round.png"
  if (Test-Path $src) {
    Copy-Item -Force $src $dst
  }
}
Write-Host "Aligned ic_launcher_round with solid black+blue launcher."

$check = Join-Path $Root 'android\app\src\main\res\mipmap-xxxhdpi\ic_launcher.png'
if (Test-Path $check) {
  $b = [System.Drawing.Bitmap]::FromFile((Resolve-Path $check).Path)
  try {
    $c0 = $b.GetPixel(0, 0)
    if ($c0.A -lt 250 -or $c0.R -gt 8) {
      Write-Warning "mipmap-xxxhdpi/ic_launcher.png corner not solid black - inspect adaptive config."
    } else {
      Write-Host "OK Android launcher has solid black corner."
    }
  } finally {
    $b.Dispose()
  }
}

Write-Host ""
Write-Host "Done. Source of truth: assets/branding/gavra_icon.png"
Write-Host "Reinstall the app on device to refresh launcher cache."
