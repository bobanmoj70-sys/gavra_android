# Bump Version Script
# Automatically syncs version between pubspec.yaml and build.gradle.kts
# Usage: .\bump_version.ps1 [major|minor|patch|build]

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('major','minor','patch','build')]
    [string]$Type = 'build'
)

# Read current version from pubspec.yaml
$pubspecPath = "pubspec.yaml"
$gradlePath = "android\app\build.gradle.kts"

$pubspecContent = Get-Content $pubspecPath -Raw
if ($pubspecContent -match 'version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)') {
    $major = [int]$matches[1]
    $minor = [int]$matches[2]
    $patch = [int]$matches[3]
    $build = [int]$matches[4]
} else {
    Write-Error "Could not parse version from pubspec.yaml"
    exit 1
}

Write-Host "Current version: $major.$minor.$patch+$build" -ForegroundColor Cyan

# Sacuvaj staru verziju pre bumpa (za min_version u Supabase)
$oldVersion = "$major.$minor.$patch"

# Bump version based on type
switch ($Type) {
    'major' {
        $major++
        $minor = 0
        $patch = 0
        $build++
    }
    'minor' {
        $minor++
        $patch = 0
        $build++
    }
    'patch' {
        $patch++
        $build++
    }
    'build' {
        $build++
    }
}

$newVersion = "$major.$minor.$patch"
$newFullVersion = "$newVersion+$build"

Write-Host "New version: $newFullVersion" -ForegroundColor Green

# Update pubspec.yaml
$pubspecContent = $pubspecContent -replace 'version:\s*\d+\.\d+\.\d+\+\d+', "version: $newFullVersion"
Set-Content -Path $pubspecPath -Value $pubspecContent -NoNewline

# Update build.gradle.kts
$gradleContent = Get-Content $gradlePath -Raw
$gradleContent = $gradleContent -replace 'versionCode\s*=\s*\d+', "versionCode = $build"
$gradleContent = $gradleContent -replace 'versionName\s*=\s*"[\d\.]+"', "versionName = `"$newVersion`""
Set-Content -Path $gradlePath -Value $gradleContent -NoNewline

Write-Host "`n✓ Updated pubspec.yaml: $newFullVersion" -ForegroundColor Green
Write-Host "✓ Updated build.gradle.kts: versionCode=$build, versionName=$newVersion" -ForegroundColor Green

# Auto-update Supabase v3_app_settings
# latest_version = nova verzija, min_version = prethodna (svaka druga obavezna)
$supabaseUrl = $null
$supabaseKey = $null

if (Test-Path '.env') {
    $envContent2 = Get-Content '.env' -Raw
    if ($envContent2 -match 'SUPABASE_URL=([^\r\n]+)') { $supabaseUrl = $matches[1].Trim() }
    if ($envContent2 -match 'SUPABASE_ANON_KEY=([^\r\n]+)') { $supabaseKey = $matches[1].Trim() }
}

if ($supabaseUrl -and $supabaseKey) {
    try {
        $headers = @{
            'apikey'        = $supabaseKey
            'Authorization' = "Bearer $supabaseKey"
            'Content-Type'  = 'application/json'
            'Prefer'        = 'return=minimal'
        }
        $body = (@{ latest_version = $newVersion; min_version = $oldVersion } | ConvertTo-Json)
        $uri = "$supabaseUrl/rest/v1/v3_app_settings?id=eq.global"
        Invoke-RestMethod -Uri $uri -Method Patch -Headers $headers -Body $body | Out-Null
        Write-Host "✓ Supabase: latest_version=$newVersion, min_version=$oldVersion" -ForegroundColor Green
    } catch {
        Write-Host "⚠ Supabase update nije uspio: $_" -ForegroundColor Yellow
        Write-Host "  Rucno postavi: latest_version=$newVersion, min_version=$oldVersion" -ForegroundColor Yellow
    }
} else {
    Write-Host "⚠ .env nije nadjen — rucno postavi u bazi:" -ForegroundColor Yellow
    Write-Host "  latest_version = '$newVersion'" -ForegroundColor Yellow
    Write-Host "  min_version    = '$oldVersion'" -ForegroundColor Yellow
}

Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "  git add pubspec.yaml android/app/build.gradle.kts"
Write-Host "  git commit -m 'chore: bump version to $newFullVersion'"
Write-Host "  git push"
