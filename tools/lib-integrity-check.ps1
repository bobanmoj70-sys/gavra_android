$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$failed = $false
$libRoot = Join-Path $root 'lib'

function Fail-Line {
    param([string]$Message)
    Write-Host "MISS $Message"
    $script:failed = $true
}

function Ok-Line {
    param([string]$Message)
    Write-Host "OK   $Message"
}

Write-Host "=== Lib Integrity Check ==="
Write-Host "Root: $root"
Write-Host ""

if (-not (Test-Path $libRoot)) {
    Fail-Line 'Folder `lib/` does not exist'
    exit 1
}

Write-Host "[1/3] Git tracked deletions under lib"
$deleted = git ls-files --deleted -- lib
if ($LASTEXITCODE -ne 0) {
    Fail-Line 'git ls-files command failed'
}
elseif ([string]::IsNullOrWhiteSpace(($deleted -join ''))) {
    Ok-Line 'No tracked deleted files in lib/'
}
else {
    foreach ($d in $deleted) {
        if (-not [string]::IsNullOrWhiteSpace($d)) {
            Fail-Line "Deleted tracked file: $d"
        }
    }
}

Write-Host ""
Write-Host "[2/3] Missing import/export/part targets"
$dartFiles = Get-ChildItem -Path $libRoot -Recurse -Filter '*.dart' -File
$refRegex = [regex]"^\s*(import|export|part)\s+'([^']+)'"
$checkedRefs = 0

foreach ($file in $dartFiles) {
    $content = Get-Content $file.FullName
    foreach ($line in $content) {
        $m = $refRegex.Match($line)
        if (-not $m.Success) {
            continue
        }

        $uri = $m.Groups[2].Value
        if ($uri.StartsWith('dart:')) { continue }

        $targetPath = $null

        if ($uri.StartsWith('package:gavra_android/')) {
            $rel = $uri.Substring('package:gavra_android/'.Length) -replace '/', [IO.Path]::DirectorySeparatorChar
            $targetPath = Join-Path $libRoot $rel
        }
        elseif ($uri.StartsWith('./') -or $uri.StartsWith('../') -or -not $uri.Contains(':')) {
            $rel = $uri -replace '/', [IO.Path]::DirectorySeparatorChar
            $targetPath = Join-Path $file.DirectoryName $rel
        }
        else {
            continue
        }

        $checkedRefs++
        if (-not (Test-Path $targetPath)) {
            $pretty = $file.FullName.Replace($root + [IO.Path]::DirectorySeparatorChar, '')
            Fail-Line "$pretty -> missing: $uri"
        }
    }
}

if ($checkedRefs -eq 0) {
    Fail-Line 'No import/export/part references were parsed (unexpected)'
}
elseif (-not $failed) {
    Ok-Line "Checked $checkedRefs local/package:gavra_android refs"
}

Write-Host ""
Write-Host "[3/3] Summary"
if ($failed) {
    Write-Host '❌ LIB INTEGRITY: FAIL'
    exit 1
}

Write-Host '✅ LIB INTEGRITY: PASS'
exit 0
