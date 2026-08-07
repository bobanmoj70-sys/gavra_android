# Gavra branding — jedini izvor istine

## Master ikona

| Fajl | Opis |
|------|------|
| **`gavra_icon.png`** | **JEDINI IZVOR ISTINE** — crna pozadina + cyan/plava slova GAVRA (512×512) |

**Boje:**
- pozadina: `#000000`
- slova: `#60C8F8`

Sve launcher ikone (Android/iOS), splash i in-app logo **moraju** poticati od ovog fajla.

## Pravila

1. **NE BRIŠI** `gavra_icon.png`.
2. **NE MENJAJ** Android `mipmap/*` / iOS `AppIcon` ručno.
3. **NE DODAVAJ** legacy `assets/logo_*.png` / `ic_launcher_512.png` — obrisani.
4. U kodu samo `GavraBranding` (`lib/config/gavra_branding.dart`).
5. Posle izmene mastera:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/sync_branding_icons.ps1
```

Skripta:
- validira crnu pozadinu + plava slova
- briše legacy alias fajlove ako se vrate
- regeneriše Android + iOS launchere
- kopira master u splash `drawable/ic_launcher_foreground.png`
- poravnava `ic_launcher_round`

## U kodu

```dart
GavraBranding.iconAsset   // assets/branding/gavra_icon.png
GavraBranding.background  // #000000
GavraBranding.letter      // #60C8F8
```
