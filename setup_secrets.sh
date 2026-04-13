#!/bin/bash
# GitHub Secrets Setup Script
# Pokrenite: bash setup_secrets.sh

# Isprovjera je li gh CLI instaliran
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI nije instaliran"
    echo "📥 Instalirajte sa: https://cli.github.com"
    exit 1
fi

# Isprovjera repozitorija
if [ ! -d ".git" ]; then
    echo "❌ Niste u root direktoriju repozitorija"
    exit 1
fi

echo "🔐 Dodavanje GitHub Secretsa..."
echo ""

# Android Secrets
echo "📱 Android Secrets..."
gh secret set ANDROID_KEYSTORE_BASE64 < temp_secrets/gavra-release-key_BASE64.txt && echo "✓ ANDROID_KEYSTORE_BASE64"
gh secret set ANDROID_KEYSTORE_PASSWORD --body "GavraRelease2024" && echo "✓ ANDROID_KEYSTORE_PASSWORD"
gh secret set ANDROID_KEY_PASSWORD --body "GavraRelease2024" && echo "✓ ANDROID_KEY_PASSWORD"
gh secret set ANDROID_KEY_ALIAS --body "gavra-release-key" && echo "✓ ANDROID_KEY_ALIAS"
gh secret set ANDROID_GOOGLE_SERVICES_JSON_BASE64 < temp_secrets/ANDROID_GOOGLE_SERVICES_JSON_BASE64.txt && echo "✓ ANDROID_GOOGLE_SERVICES_JSON_BASE64"
gh secret set GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64 < temp_secrets/GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64.txt && echo "✓ GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64"
gh secret set APP_ENV_BASE64 --body "$(base64 < .env | tr -d '\n')" && echo "✓ APP_ENV_BASE64"

echo ""
echo "🍎 iOS Secrets..."
gh secret set APP_STORE_CONNECT_KEY_IDENTIFIER --body "Q95YKW2L9S" && echo "✓ APP_STORE_CONNECT_KEY_IDENTIFIER"
gh secret set APP_STORE_CONNECT_ISSUER_ID --body "d8b50e72-6330-401d-9aaf-4ead356495cb" && echo "✓ APP_STORE_CONNECT_ISSUER_ID"
gh secret set APP_STORE_CONNECT_PRIVATE_KEY_BASE64 < temp_secrets/APP_STORE_CONNECT_PRIVATE_KEY_BASE64.txt && echo "✓ APP_STORE_CONNECT_PRIVATE_KEY_BASE64"
gh secret set CERTIFICATE_PRIVATE_KEY_BASE64 < temp_secrets/CERTIFICATE_PRIVATE_KEY_BASE64.txt && echo "✓ CERTIFICATE_PRIVATE_KEY_BASE64"
echo ""
echo "✅ Svi secretsi su dodani!"
