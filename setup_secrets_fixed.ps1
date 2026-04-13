#!/usr/bin/env pwsh
# GitHub Secrets Setup Script za Windows
# Pokrenite: .\setup_secrets.ps1

Write-Host ""
Write-Host "=== GitHub Secrets Setup ===" -ForegroundColor Cyan
Write-Host ""

# Isprovjera je li gh CLI instaliran
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "GitHub CLI nije instaliran" -ForegroundColor Red
    Write-Host "Instalirajte sa: https://cli.github.com" -ForegroundColor Yellow
    exit 1
}

# Isprovjera repozitorija
if (-not (Test-Path ".git")) {
    Write-Host "Niste u root direktoriju repozitorija" -ForegroundColor Red
    exit 1
}

Write-Host "Dodavanje GitHub Secretsa..." -ForegroundColor Cyan
Write-Host ""

$successCount = 0
$totalCount = 0

# Android
Write-Host "Android Secrets:" -ForegroundColor Yellow

$totalCount++
$content = Get-Content "temp_secrets/gavra-release-key_BASE64.txt" -Raw
gh secret set ANDROID_KEYSTORE_BASE64 --body $content
if ($?) { Write-Host "OK: ANDROID_KEYSTORE_BASE64"; $successCount++ } else { Write-Host "FAIL: ANDROID_KEYSTORE_BASE64" }

$totalCount++
gh secret set ANDROID_KEYSTORE_PASSWORD --body "GavraRelease2024"
if ($?) { Write-Host "OK: ANDROID_KEYSTORE_PASSWORD"; $successCount++ } else { Write-Host "FAIL: ANDROID_KEYSTORE_PASSWORD" }

$totalCount++
gh secret set ANDROID_KEY_PASSWORD --body "GavraRelease2024"
if ($?) { Write-Host "OK: ANDROID_KEY_PASSWORD"; $successCount++ } else { Write-Host "FAIL: ANDROID_KEY_PASSWORD" }

$totalCount++
gh secret set ANDROID_KEY_ALIAS --body "gavra-release-key"
if ($?) { Write-Host "OK: ANDROID_KEY_ALIAS"; $successCount++ } else { Write-Host "FAIL: ANDROID_KEY_ALIAS" }

$totalCount++
$content = Get-Content "temp_secrets/ANDROID_GOOGLE_SERVICES_JSON_BASE64.txt" -Raw
gh secret set ANDROID_GOOGLE_SERVICES_JSON_BASE64 --body $content
if ($?) { Write-Host "OK: ANDROID_GOOGLE_SERVICES_JSON_BASE64"; $successCount++ } else { Write-Host "FAIL: ANDROID_GOOGLE_SERVICES_JSON_BASE64" }

$totalCount++
$content = Get-Content "temp_secrets/GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64.txt" -Raw
gh secret set GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64 --body $content
if ($?) { Write-Host "OK: GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64"; $successCount++ } else { Write-Host "FAIL: GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64" }

$totalCount++
$content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-Content ".env" -Raw)))
gh secret set APP_ENV_BASE64 --body $content
if ($?) { Write-Host "OK: APP_ENV_BASE64"; $successCount++ } else { Write-Host "FAIL: APP_ENV_BASE64" }

Write-Host ""
Write-Host "iOS Secrets:" -ForegroundColor Yellow

$totalCount++
gh secret set APP_STORE_CONNECT_KEY_IDENTIFIER --body "Q95YKW2L9S"
if ($?) { Write-Host "OK: APP_STORE_CONNECT_KEY_IDENTIFIER"; $successCount++ } else { Write-Host "FAIL: APP_STORE_CONNECT_KEY_IDENTIFIER" }

$totalCount++
gh secret set APP_STORE_CONNECT_ISSUER_ID --body "d8b50e72-6330-401d-9aaf-4ead356495cb"
if ($?) { Write-Host "OK: APP_STORE_CONNECT_ISSUER_ID"; $successCount++ } else { Write-Host "FAIL: APP_STORE_CONNECT_ISSUER_ID" }

$totalCount++
$content = Get-Content "temp_secrets/APP_STORE_CONNECT_PRIVATE_KEY_BASE64.txt" -Raw
gh secret set APP_STORE_CONNECT_PRIVATE_KEY_BASE64 --body $content
if ($?) { Write-Host "OK: APP_STORE_CONNECT_PRIVATE_KEY_BASE64"; $successCount++ } else { Write-Host "FAIL: APP_STORE_CONNECT_PRIVATE_KEY_BASE64" }

$totalCount++
$content = Get-Content "temp_secrets/CERTIFICATE_PRIVATE_KEY_BASE64.txt" -Raw
gh secret set CERTIFICATE_PRIVATE_KEY_BASE64 --body $content
if ($?) { Write-Host "OK: CERTIFICATE_PRIVATE_KEY_BASE64"; $successCount++ } else { Write-Host "FAIL: CERTIFICATE_PRIVATE_KEY_BASE64" }

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Rezultat: $successCount/$totalCount secretsa" -ForegroundColor Green
Write-Host "========================================"
