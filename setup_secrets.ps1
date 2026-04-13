# GitHub Secrets Setup Script za Windows
# Pokrenite: .\setup_secrets.ps1

# Isprovjera je li gh CLI instaliran
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "❌ GitHub CLI nije instaliran" -ForegroundColor Red
    Write-Host "📥 Instalirajte sa: https://cli.github.com" -ForegroundColor Yellow
    exit 1
}

# Isprovjera repozitorija
if (-not (Test-Path ".git")) {
    Write-Host "❌ Niste u root direktoriju repozitorija" -ForegroundColor Red
    exit 1
}

Write-Host "🔐 Dodavanje GitHub Secretsa..." -ForegroundColor Cyan
Write-Host ""

# Helper funkcija
function Add-Secret {
    param(
        [string]$Name,
        [string]$Value,
        [string]$FilePath
    )
    
    if ($FilePath) {
        if (Test-Path $FilePath) {
            $content = Get-Content $FilePath -Raw
            gh secret set $Name --body $content
        } else {
            Write-Host "❌ Fajl nije pronađen: $FilePath" -ForegroundColor Red
            return $false
        }
    } else {
        gh secret set $Name --body $Value
    }
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ $Name" -ForegroundColor Green
        return $true
    } else {
        Write-Host "❌ $Name - Greška pri dodavanju" -ForegroundColor Red
        return $false
    }
}

$successCount = 0
$totalCount = 0

Write-Host "📱 Android Secrets..." -ForegroundColor Cyan

$totalCount++; if (Add-Secret -Name "ANDROID_KEYSTORE_BASE64" -FilePath "temp_secrets/gavra-release-key_BASE64.txt") { $successCount++ }

$totalCount++; if (Add-Secret -Name "ANDROID_KEYSTORE_PASSWORD" -Value "GavraRelease2024") { $successCount++ }

$totalCount++; if (Add-Secret -Name "ANDROID_KEY_PASSWORD" -Value "GavraRelease2024") { $successCount++ }

$totalCount++; if (Add-Secret -Name "ANDROID_KEY_ALIAS" -Value "gavra-release-key") { $successCount++ }

$totalCount++; if (Add-Secret -Name "ANDROID_GOOGLE_SERVICES_JSON_BASE64" -FilePath "temp_secrets/ANDROID_GOOGLE_SERVICES_JSON_BASE64.txt") { $successCount++ }

$totalCount++; if (Add-Secret -Name "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64" -FilePath "temp_secrets/GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64.txt") { $successCount++ }

$appEnvBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-Content ".env" -Raw)))
$totalCount++; if (Add-Secret -Name "APP_ENV_BASE64" -Value $appEnvBase64) { $successCount++ }

Write-Host ""
Write-Host "🍎 iOS Secrets..." -ForegroundColor Cyan

$totalCount++; if (Add-Secret -Name "APP_STORE_CONNECT_KEY_IDENTIFIER" -Value "Q95YKW2L9S") { $successCount++ }

$totalCount++; if (Add-Secret -Name "APP_STORE_CONNECT_ISSUER_ID" -Value "d8b50e72-6330-401d-9aaf-4ead356495cb") { $successCount++ }

$totalCount++; if (Add-Secret -Name "APP_STORE_CONNECT_PRIVATE_KEY_BASE64" -FilePath "temp_secrets/APP_STORE_CONNECT_PRIVATE_KEY_BASE64.txt") { $successCount++ }

$totalCount++; if (Add-Secret -Name "CERTIFICATE_PRIVATE_KEY_BASE64" -FilePath "temp_secrets/CERTIFICATE_PRIVATE_KEY_BASE64.txt") { $successCount++ }

Write-Host ""
$color = if ($successCount -eq $totalCount) { "Green" } else { "Yellow" }
Write-Host "Rezultat: $successCount/$totalCount secretsa uspjesno dodano" -ForegroundColor $color

if ($successCount -eq $totalCount) {
    Write-Host "Svi secretsi su dodani!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Sada mozete pokrenuti workflow:" -ForegroundColor Cyan
    Write-Host "   https://github.com/bobanmoj70-sys/gavra_android/actions/workflows/production-release.yml" -ForegroundColor Yellow
} else {
    Write-Host "Neki secretsi nisu dodani. Provjeri greske gore." -ForegroundColor Yellow
}
