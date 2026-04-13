#!/usr/bin/env python3
"""
GitHub Secrets Setup Helper
Kreiram sve potrebne secretse za production release workflow
"""

import json
import base64
import os
from pathlib import Path

# Definirajmo sve potrebne secretse
SECRETS_CONFIG = {
    # Android
    "ANDROID_KEYSTORE_BASE64": {
        "file": "temp_secrets/gavra-release-key_BASE64.txt",
        "type": "base64",
        "required": True,
        "description": "Android keystore za signing"
    },
    "ANDROID_KEYSTORE_PASSWORD": {
        "value": "GavraRelease2024",
        "type": "string",
        "required": True,
        "description": "Lozinka za keystore"
    },
    "ANDROID_KEY_PASSWORD": {
        "value": "GavraRelease2024",
        "type": "string",
        "required": True,
        "description": "Lozinka za privatni ključ"
    },
    "ANDROID_KEY_ALIAS": {
        "value": "gavra-release-key",
        "type": "string",
        "required": True,
        "description": "Alias za privatni ključ u keystore-u"
    },
    "ANDROID_GOOGLE_SERVICES_JSON_BASE64": {
        "file": "temp_secrets/ANDROID_GOOGLE_SERVICES_JSON_BASE64.txt",
        "type": "base64",
        "required": True,
        "description": "Google Services JSON (Base64)"
    },
    "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64": {
        "file": "temp_secrets/GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64.txt",
        "type": "base64",
        "required": True,
        "description": "Google Play service account JSON (Base64)"
    },
    "APP_ENV_BASE64": {
        "file": ".env",
        "type": "text_to_base64",
        "required": True,
        "description": "Glavno app okruženje konfiguracija (.env) kao Base64"
    },
    
    # iOS
    "APP_STORE_CONNECT_KEY_IDENTIFIER": {
        "value": "Q95YKW2L9S",
        "type": "string",
        "required": True,
        "description": "App Store Connect Key ID"
    },
    "APP_STORE_CONNECT_ISSUER_ID": {
        "value": "d8b50e72-6330-401d-9aaf-4ead356495cb",
        "type": "string",
        "required": True,
        "description": "App Store Connect Issuer ID"
    },
    "APP_STORE_CONNECT_PRIVATE_KEY_BASE64": {
        "file": "temp_secrets/APP_STORE_CONNECT_PRIVATE_KEY_BASE64.txt",
        "type": "base64",
        "required": True,
        "description": "App Store Connect privatni ključ (Base64)"
    },
    "CERTIFICATE_PRIVATE_KEY_BASE64": {
        "file": "temp_secrets/CERTIFICATE_PRIVATE_KEY_BASE64.txt",
        "type": "base64",
        "required": True,
        "description": "iOS certificate privatni ključ (Base64)"
    },
}

def get_secret_value(secret_name, config):
    """Preuzmi vrijednost secretsa"""
    if "value" in config:
        return config["value"]
    elif "file" in config:
        filepath = Path(config["file"])
        if not filepath.exists():
            # Pokušaj sa apsolutnom putanjom
            filepath = Path(__file__).parent / config["file"]
        
        if filepath.exists():
            content = filepath.read_text(encoding="utf-8")
            if config.get("type") == "text_to_base64":
                return base64.b64encode(content.encode("utf-8")).decode("utf-8")
            return content.strip()
        else:
            return None
    return None

def validate_secrets():
    """Validacija svih potrebnih secretsa"""
    print("🔍 Validacija GitHub secretsa...\n")
    
    missing = []
    invalid = []
    
    for secret_name, config in SECRETS_CONFIG.items():
        value = get_secret_value(secret_name, config)
        is_required = config.get("required", False)
        
        if not value and is_required:
            missing.append((secret_name, config["description"]))
        elif value:
            print(f"✅ {secret_name}")
            if config["type"] in ("base64", "text_to_base64"):
                try:
                    # Testira da li je valid base64
                    base64.b64decode(value)
                    print(f"   └─ Base64: Valid ({len(value)} chars)")
                except:
                    invalid.append((secret_name, "Invalid base64"))
                    print(f"   └─ Base64: ⚠️  INVALID")
        else:
            if is_required:
                print(f"❌ {secret_name} - NEDOSTAJE")
            else:
                print(f"⚠️  {secret_name} - Opciono (nije pronađeno)")
    
    print("\n" + "="*70)
    
    if missing:
        print("\n⚠️  NEDOSTAJU OBVEZNI SECRETSI:\n")
        for secret_name, desc in missing:
            print(f"   • {secret_name}")
            print(f"     └─ {desc}\n")
        return False
    
    if invalid:
        print("\n❌ NEVALJANI SECRETSI:\n")
        for secret_name, reason in invalid:
            print(f"   • {secret_name}: {reason}\n")
        return False
    
    print("\n✅ Svi potrebni secretsi su validni!\n")
    return True

def generate_github_cli_commands():
    """Generira GitHub CLI komande za dodavanje secretsa"""
    print("\n📝 GitHub CLI Komande:\n")
    print("# Pokrenite ove komande u terminalu (trebate GitHub CLI)\n")
    
    for secret_name, config in SECRETS_CONFIG.items():
        value = get_secret_value(secret_name, config)
        if value:
            # Za Base64, prikaži samo prvu liniju
            if config["type"] == "base64" and len(value) > 100:
                display_value = value[:100] + "..."
            else:
                display_value = value
            
            print(f"# {config['description']}")
            print(f'gh secret set {secret_name} --body "{display_value}"')
            print()

if __name__ == "__main__":
    print("="*70)
    print("GitHub Secrets Setup Helper")
    print("="*70 + "\n")
    
    if validate_secrets():
        print("\n🚀 Workflow je spreman za pokretanje!\n")
    else:
        print("\n⚠️  Trebate dodati nedostajuće secretse prije pokretanja workflow-a\n")
        print("👉 Idite na: https://github.com/bobanmoj70-sys/gavra_android/settings/secrets/actions\n")
