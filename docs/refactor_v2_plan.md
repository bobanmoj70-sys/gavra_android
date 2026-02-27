# Refaktor plan — migracija na v2_ tabele

> **Legenda:** ⬜ Nije početo · ✅ Završeno
>
> **Redosled:** Najpre sekcija 1, zatim 2, na kraju 3. `realtime_manager.dart` uvek poslednji.

---

## SEKCIJA 1 — Jednostavne zamene

> Jedan fajl, direktna zamena stringa tabele.

| # | Stara tabela | Nova tabela | Fajl | Status |
|---|---|---|---|:---:|
| 1 | `weather_alerts_log` | `v2_weather_alerts_log` | `v2_weather_alert_service.dart` | ✅ |
| 2 | `racun_sequence` | `v2_racun_sequence` | `racun_service.dart` | ⬜ |
| 3 | `adrese` | `v2_adrese` | `adresa_supabase_service.dart` | ⬜ |
| 4 | `vozac_raspored` | `v2_vozac_raspored` | `vozac_raspored_service.dart` | ⬜ |
| 5 | `vozac_putnik` | `v2_vozac_putnik` | `vozac_putnik_service.dart` | ⬜ |
| 6 | `vozac_lokacije` | `v2_vozac_lokacije` | `driver_location_service.dart` | ⬜ |
| 7 | `vozila_istorija` | `v2_vozila_servis` | `vozila_service.dart` | ⬜ |
| 8 | `app_settings` | `v2_app_settings` | `app_settings_service.dart` | ⬜ |
| 9 | `finansije_troskovi` | `v2_finansije_troskovi` | `finansije_service.dart` | ⬜ |
| 10 | `pumpa_stanje` | `v2_pumpa_stanje` | `gorivo_service.dart` | ⬜ |
| 11 | `pumpa_config` | `v2_pumpa_config` | `gorivo_service.dart` | ⬜ |
| 12 | `pumpa_punjenja` | `v2_pumpa_punjenja` | `gorivo_service.dart` | ⬜ |
| 13 | `pumpa_tocenja` | `v2_pumpa_tocenja` | `gorivo_service.dart` | ⬜ |

---

## SEKCIJA 2 — Srednje složene zamene

> Više fajlova, ali još uvek direktna zamena stringa.

### `kapacitet_polazaka` → `v2_kapacitet_polazaka` ⬜
- `kapacitet_service.dart`
- `seat_request_service.dart`
- `realtime_manager.dart`

### `vozaci` → `v2_vozaci` ⬜
- `vozac_service.dart`
- `voznje_log_service.dart`
- `putnik_service.dart`
- `auth_manager.dart`
- `realtime_manager.dart`

### `vozila` → `v2_vozila` ⬜
- `vozila_service.dart`
- `gorivo_service.dart`
- `realtime_manager.dart`

### `pin_zahtevi` → `v2_pin_zahtevi` ⬜
- `pin_zahtev_service.dart`
- `registrovani_putnik_service.dart`

### `push_tokens` → `v2_push_tokens` ⬜
- `push_token_service.dart`
- `realtime_notification_service.dart`
- `auth_manager.dart`

### `voznje_log` → `v2_voznje_log` ⬜
- `voznje_log_service.dart`
- `finansije_service.dart`
- `putnik_service.dart`
- `registrovani_putnik_service.dart`
- `cena_obracun_service.dart`
- `realtime_manager.dart`

### `seat_requests` → `v2_polasci` ⬜
- `seat_request_service.dart`
- `putnik_service.dart`
- `local_notification_service.dart`
- `realtime_manager.dart`

---

## SEKCIJA 3 — Kompleksna zamena (arhitektura)

### `registrovani_putnici` → `v2_radnici` / `v2_ucenici` / `v2_dnevni` / `v2_posiljke`

> **Problem:** Stara tabela ima `tip` kolonu — sav kod pretpostavlja jednu tabelu za sve tipove putnika.
> **Odluka:** ⬜ VIEW  /  ⬜ Pravi refaktor

| Fajl | Tip | Status |
|---|---|:---:|
| `registrovani_putnik_service.dart` | servis | ⬜ |
| `putnik_service.dart` | servis | ⬜ |
| `seat_request_service.dart` | servis | ⬜ |
| `pin_zahtev_service.dart` | servis | ⬜ |
| `finansije_service.dart` | servis | ⬜ |
| `local_notification_service.dart` | servis | ⬜ |
| `notification_navigation_service.dart` | servis | ⬜ |
| `putnik_push_service.dart` | servis | ⬜ |
| `realtime_manager.dart` | servis | ⬜ |
| `registrovani_putnik_login_screen.dart` | screen | ⬜ |
| `registrovani_putnik_profil_screen.dart` | screen | ⬜ |
| `registrovani_putnici_screen.dart` | screen | ⬜ |
| `vozac_action_log_screen.dart` | screen | ⬜ |
| `pin_zahtevi_screen.dart` | screen | ⬜ |
| `registrovani_putnik_dialog.dart` | widget | ⬜ |
| `pin_dialog.dart` | widget | ⬜ |

---

## Napomene

- Stare tabele ostaju u bazi dok se refaktor ne testira u celosti
- Svaki servis se testira posebno pre sledećeg
- `realtime_manager.dart` menja se uvek poslednji — zavisi od svih ostalih
