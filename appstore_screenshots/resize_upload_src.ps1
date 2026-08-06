Add-Type -AssemblyName System.Drawing
$srcDir = Join-Path $PSScriptRoot "..\..\Desktop\production final\ios\slike"
$outDir = Join-Path $PSScriptRoot "iphone_upload"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$w = 1284; $h = 2778
Get-ChildItem -Path $srcDir -File | Sort-Object Name | ForEach-Object {
  $dest = Join-Path $outDir ($_.BaseName + ".png")
  $img = [System.Drawing.Image]::FromFile($_.FullName)
  $bmp = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.Clear([System.Drawing.Color]::White)
  $g.DrawImage($img, 0, 0, $w, $h)
  $bmp.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose(); $img.Dispose()
  Write-Output ("OK " + $_.Name + " -> " + $dest + " " + (Get-Item $dest).Length)
}
