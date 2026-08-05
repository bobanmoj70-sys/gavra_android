# Gavra branding — jedini izvor istine

## Master ikona

| Fajl | Opis |
|------|------|
| **`gavra_icon.png`** | **JEDINI IZVOR ISTINE** — crna pozadina + plava slova GAVRA 013 (512×512) |

Sve launcher ikone (Android/iOS), splash i in-app logo **moraju** poticati od ovog fajla.

## Pravila

1. **NE BRIŠI** `gavra_icon.png` pri cleanup-u workspace-a.
2. **NE MENJAJ** Android `mipmap/*`, iOS `AppIcon`, niti legacy `assets/logo_*.png` ručno.
3. Posle izmene mastera pokreni:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/sync_branding_icons.ps1
```

Skripta:
- proverava da master postoji i da ima crnu pozadinu
- kopira master u legacy putanje (kompatibilnost)
- regeneriše Android + iOS launcher ikone preko `flutter_launcher_icons`
- poravnava `ic_launcher_round` sa punom crnom pozadinom

## U kodu

Koristi isključivo:

```dart
GavraBranding.iconAsset  // → assets/branding/gavra_icon.png
```

(`lib/config/gavra_branding.dart`)

## Legacy aliasi (generisani — ne editovati)

Ovi fajlovi se **overwrite**-uju skriptom iz mastera:

- `assets/ic_launcher_512.png`
- `assets/logo_original.png`
- `assets/logo_transparent.png`
