param(
  [string]$File = "pubspec.yaml",
  [int]$PatchInc = 1,
  [int]$BuildInc = 1
)

$content = Get-Content $File -Raw
if ($content -notmatch 'version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)') {
  throw "Ne mogu da nađem version liniju u formatu x.y.z+build"
}

$major = [int]$matches[1]
$minor = [int]$matches[2]
$patch = [int]$matches[3] + $PatchInc
$build = [int]$matches[4] + $BuildInc

$newVersion = "version: $major.$minor.$patch+$build"
$content = [regex]::Replace($content, 'version:\s*\d+\.\d+\.\d+\+\d+', $newVersion, 1)

Set-Content $File $content -Encoding UTF8
Write-Host "✅ $newVersion"