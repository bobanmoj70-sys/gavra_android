# GitHub Secrets Setup za Production Release

Trebate dodati sljedeće GitHub Secretse:

## Android Secrets

1. **ANDROID_KEYSTORE_BASE64**
   - Vrijednost: Vidi `temp_secrets/gavra-release-key_BASE64.txt`

2. **ANDROID_KEYSTORE_PASSWORD**
   - Vrijednost: `GavraRelease2024`

3. **ANDROID_KEY_PASSWORD**
   - Vrijednost: `GavraRelease2024`

4. **ANDROID_KEY_ALIAS**
   - Vrijednost: `gavra-release-key`

5. **ANDROID_GOOGLE_SERVICES_JSON_BASE64**
   - Vrijednost: Vidi `temp_secrets/ANDROID_GOOGLE_SERVICES_JSON_BASE64.txt`

6. **GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64**
   - Vrijednost: Vidi `temp_secrets/GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64.txt`

7. **APP_ENV_BASE64**
   - Vrijednost: Base64 sadržaj lokalnog `.env` fajla (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, itd.)

## iOS Secrets

8. **APP_STORE_CONNECT_KEY_IDENTIFIER**
   - Vrijednost: `Q95YKW2L9S`

9. **APP_STORE_CONNECT_ISSUER_ID**
   - Vrijednost: `d8b50e72-6330-401d-9aaf-4ead356495cb`

10. **APP_STORE_CONNECT_PRIVATE_KEY_BASE64**
    - Vrijednost: Vidi `temp_secrets/APP_STORE_CONNECT_PRIVATE_KEY_BASE64.txt`

11. **CERTIFICATE_PRIVATE_KEY_BASE64**
    - Vrijednost: Vidi `temp_secrets/CERTIFICATE_PRIVATE_KEY_BASE64.txt`

## Kako dodati secretse

1. Idite na: https://github.com/bobanmoj70-sys/gavra_android/settings/secrets/actions
2. Za svaki secret, kliknite "New repository secret"
3. Unesite **Ime** i **Vrijednost**
4. Kliknite "Add secret"

## PowerShell Script za kopiranje

Kopirajte Base64 stringove sa:
```powershell
Get-Content 'c:\Users\Bojan\gavra_android\temp_secrets\FILENAME.txt' | Set-Clipboard
```

Zatim ga paste-ujte u GitHub.
