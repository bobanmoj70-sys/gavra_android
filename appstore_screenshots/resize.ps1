Add-Type -AssemblyName System.Drawing

$src = "C:\Users\Bojan\gavra_android\appstore_screenshots"
$iphoneDir = Join-Path $src "iphone_6.9"
$ipadDir = Join-Path $src "ipad_13"

New-Item -ItemType Directory -Path $iphoneDir -Force | Out-Null
New-Item -ItemType Directory -Path $ipadDir -Force | Out-Null

$iphoneW = 1320; $iphoneH = 2868
$ipadW = 2064; $ipadH = 2752

function Resize-Stretch($srcPath, $destPath, $w, $h) {
    $img = [System.Drawing.Image]::FromFile($srcPath)
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.DrawImage($img, 0, 0, $w, $h)
    $bmp.Save($destPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose(); $img.Dispose()
}

function Resize-Fit($srcPath, $destPath, $canvasW, $canvasH) {
    # Crop-fill: fills entire canvas, cropping excess instead of leaving white bars
    $img = [System.Drawing.Image]::FromFile($srcPath)
    $ratioSrc = $img.Width / $img.Height
    $ratioCanvas = $canvasW / $canvasH
    if ($ratioSrc -gt $ratioCanvas) {
        # source wider than canvas -> match height, crop width
        $newH = $canvasH
        $newW = [int]($canvasH * $ratioSrc)
    } else {
        # source taller than canvas -> match width, crop height
        $newW = $canvasW
        $newH = [int]($canvasW / $ratioSrc)
    }
    $x = [int](($canvasW - $newW) / 2)
    $y = [int](($canvasH - $newH) / 2)

    $bmp = New-Object System.Drawing.Bitmap $canvasW, $canvasH
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.DrawImage($img, $x, $y, $newW, $newH)
    $bmp.Save($destPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose(); $img.Dispose()
}

1..5 | ForEach-Object {
    $srcFile = Join-Path $src "$_.PNG"
    Resize-Stretch $srcFile (Join-Path $iphoneDir "$_.png") $iphoneW $iphoneH
    Resize-Fit $srcFile (Join-Path $ipadDir "$_.png") $ipadW $ipadH
    Write-Host "Processed $_.PNG"
}

Write-Host "Done."
