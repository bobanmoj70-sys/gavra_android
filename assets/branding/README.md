# Gavra branding — jedini izvor istine

## Master ikona

| Fajl | Opis |
|------|------|
| **`gavra_icon.png`** | **JEDINI IZVOR ISTINE** — crna pozadina + cyan cursive **Gavra 013** (512×512, **full-bleed kvadrat**) |

**Stil (kao Google Play):**
- pozadina: `#000000`
- slova: `#60C8F8` (cursive „Gavra“ + „013“)
- zaobljeni uglovi: **ne pečemo u master** — OS / Play / UI maska (~22% radius)

Master **mora** ostati neprozirni kvadrat (Android adaptive, iOS App Store, Play high-res).
Zaobljene ivice idu preko:
- Android launcher (adaptive maska OS-a)
- `ic_launcher.png` mipmap → rounded square (~22%)
- `ic_launcher_round.png` → krug
- iOS → sistemska maska
- u aplikaciji → `GavraBrandIcon`

## Pravila

1. **NE BRIŠI** `gavra_icon.png`.
2. **NE MENJAJ** Android `mipmap/*` / iOS `AppIcon` ručno.
3. **NE DODAVAJ** legacy `assets/logo_*.png` / `ic_launcher_512.png` / `gavra_icon_rounded.png`.
4. U kodu samo `GavraBranding` / `GavraBrandIcon` (`lib/config/gavra_branding.dart`).
5. Posle izmene mastera:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/sync_branding_icons.ps1
```

Skripta:
- validira crnu pozadinu + plava slova
- briše legacy alias fajlove ako se vrate
- regeneriše Android + iOS launchere (`flutter_launcher_icons`)
- kopira master u splash `drawable/ic_launcher_foreground.png`
- peče **Play-style** rounded / round maske na Android mipmap bitmape

## U kodu

```dart
GavraBranding.iconAsset           // assets/branding/gavra_icon.png
GavraBranding.background          // #000000
GavraBranding.letter              // #60C8F8
GavraBranding.cornerRadiusFactor  // 0.22 (Play-style)

// UI logo (zaobljeni uglovi):
GavraBrandIcon(height: 180)
```
