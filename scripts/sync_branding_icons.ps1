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
  'assets\logo_gavra.jpg',
  'assets\branding\gavra_icon_rounded.png'
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
# Master stays FULL SQUARE (opaque) — Android adaptive + iOS + Play require full-bleed.
$splashFg = Join-Path $Root 'android\app\src\main\res\drawable\ic_launcher_foreground.png'
Copy-Item -Force $Master $splashFg
Write-Host "Synced splash bitmap: android/app/src/main/res/drawable/ic_launcher_foreground.png"

# Bake Play-style masks into legacy mipmap bitmaps (API <26 / some launchers):
#   ic_launcher.png       -> rounded square (~22% radius, like Play Store)
#   ic_launcher_round.png -> circle
# Adaptive XML icons still use full-bleed master; OS applies its own mask.
$maskPy = Join-Path $Root 'scripts\_mask_launcher_icons.py'
@'
"""Apply Play-style corner masks to Android mipmap launcher PNGs."""
from __future__ import annotations

import glob
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
# Material / Play-like continuous corner ≈ 20–25% of edge
RADIUS_RATIO = 0.22


def apply_rounded(path: str) -> None:
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    r = max(1, int(min(w, h) * RADIUS_RATIO))
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w - 1, h - 1), radius=r, fill=255)
    out = im.copy()
    out.putalpha(mask)
    out.save(path, "PNG")
    print(f"  rounded r={r}: {os.path.relpath(path, ROOT)}")


def apply_circle(path: str) -> None:
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, w - 1, h - 1), fill=255)
    out = im.copy()
    out.putalpha(mask)
    out.save(path, "PNG")
    print(f"  circle: {os.path.relpath(path, ROOT)}")


def main() -> int:
    dens = ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi")
    for d in dens:
        base = os.path.join(ROOT, "android", "app", "src", "main", "res", f"mipmap-{d}")
        sq = os.path.join(base, "ic_launcher.png")
        rnd = os.path.join(base, "ic_launcher_round.png")
        if os.path.isfile(sq):
            # Start round from the (still square) launcher, then mask both
            if os.path.isfile(rnd):
                Image.open(sq).convert("RGBA").save(rnd, "PNG")
            apply_rounded(sq)
            if os.path.isfile(rnd):
                # reload unmasked: re-read from rounded already applied to sq —
                # so rebuild round from master-sized copy before rounded alpha.
                pass
        # Rebuild round from pre-mask: flutter output was square; we overwrote sq.
        # Better: mask from flutter originals by reading both before write.
    return 0


if __name__ == "__main__":
    # Two-pass safe: load all first, then write
    dens = ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi")
    loaded = []
    for d in dens:
        base = os.path.join(ROOT, "android", "app", "src", "main", "res", f"mipmap-{d}")
        sq = os.path.join(base, "ic_launcher.png")
        if not os.path.isfile(sq):
            continue
        im = Image.open(sq).convert("RGBA")
        loaded.append((base, im))

    for base, im in loaded:
        w, h = im.size
        r = max(1, int(min(w, h) * RADIUS_RATIO))

        # Rounded square (Play style)
        m_round = Image.new("L", (w, h), 0)
        ImageDraw.Draw(m_round).rounded_rectangle((0, 0, w - 1, h - 1), radius=r, fill=255)
        out_sq = im.copy()
        out_sq.putalpha(m_round)
        sq_path = os.path.join(base, "ic_launcher.png")
        out_sq.save(sq_path, "PNG")
        print(f"  rounded r={r}/{w}: {os.path.relpath(sq_path, ROOT)}")

        # Circle for round launcher
        m_circ = Image.new("L", (w, h), 0)
        ImageDraw.Draw(m_circ).ellipse((0, 0, w - 1, h - 1), fill=255)
        out_ci = im.copy()
        out_ci.putalpha(m_circ)
        ci_path = os.path.join(base, "ic_launcher_round.png")
        out_ci.save(ci_path, "PNG")
        print(f"  circle: {os.path.relpath(ci_path, ROOT)}")

    # Verify xxxhdpi corner is transparent
    check = os.path.join(
        ROOT, "android", "app", "src", "main", "res", "mipmap-xxxhdpi", "ic_launcher.png"
    )
    if os.path.isfile(check):
        px = Image.open(check).convert("RGBA").getpixel((0, 0))
        if px[3] > 10:
            print("WARNING: xxxhdpi corner not transparent after mask:", px)
            sys.exit(2)
        print("OK Android mipmap launchers have Play-style rounded / round masks.")
    sys.exit(0)
'@ | Set-Content -Encoding UTF8 $maskPy

Write-Host "Applying Play-style rounded / round masks to Android mipmaps..."
& python $maskPy
if ($LASTEXITCODE -ne 0) {
  throw "mask_launcher_icons failed with exit $LASTEXITCODE"
}
Remove-Item -Force $maskPy -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Done. Source of truth: assets/branding/gavra_icon.png (full-bleed square)"
Write-Host "  - Android adaptive / iOS / splash: full square (OS applies mask)"
Write-Host "  - Android mipmap ic_launcher: rounded square (~22%)"
Write-Host "  - Android mipmap ic_launcher_round: circle"
Write-Host "Reinstall the app on device to refresh launcher cache."
