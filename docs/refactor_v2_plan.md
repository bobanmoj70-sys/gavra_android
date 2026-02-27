# Refaktor plan — migracija na v2_ tabele

> **Legenda:** ✅ Završeno
>
> **Status: SVE SEKCIJE ZAVRŠENE, V2MasterRealtimeManager je jedini globalni singleton — 2026-02-27**

---

## SEKCIJA 1 — Jednostavne zamene

> Jedan fajl, direktna zamena stringa tabele.

| # | Stara tabela | Nova tabela | Fajl | Status |
|---|---|---|---|:---:|
| 1 | `weather_alerts_log` | `v2_weather_alerts_log` | `v2_weather_alert_service.dart` | ✅ |
| 2 | `racun_sequence` | `v2_racun_sequence` | `racun_service.dart` | ✅ |
| 3 | `adrese` | `v2_adrese` | `adresa_supabase_service.dart` | ✅ |
| 4 | `vozac_raspored` | `v2_vozac_raspored` | `vozac_raspored_service.dart` | ✅ |
| 5 | `vozac_putnik` | `v2_vozac_putnik` | `vozac_putnik_service.dart` | ✅ |
| 6 | `vozac_lokacije` | `v2_vozac_lokacije` | `driver_location_service.dart` | ✅ |
| 7 | `vozila_istorija` | `v2_vozila_servis` | `vozila_service.dart` | ✅ |
| 8 | `app_settings` | `v2_app_settings` | `app_settings_service.dart` | ✅ |
| 9 | `finansije_troskovi` | `v2_finansije_troskovi` | `finansije_service.dart` | ✅ |
| 10 | `pumpa_stanje` | `v2_pumpa_stanje` | `gorivo_service.dart` | ✅ |
| 11 | `pumpa_config` | `v2_pumpa_config` | `gorivo_service.dart` | ✅ |
| 12 | `pumpa_punjenja` | `v2_pumpa_punjenja` | `gorivo_service.dart` | ✅ |
| 13 | `pumpa_tocenja` | `v2_pumpa_tocenja` | `gorivo_service.dart` | ✅ |

---

## SEKCIJA 2 — Srednje složene zamene

> Više fajlova, ali još uvek direktna zamena stringa.

### `kapacitet_polazaka` → `v2_kapacitet_polazaka` ✅
- `kapacitet_service.dart`
- `seat_request_service.dart`
- `realtime_manager.dart`

### `vozaci` → `v2_vozaci` ✅
- `vozac_service.dart`
- `voznje_log_service.dart`
- `putnik_service.dart`
- `auth_manager.dart`
- `realtime_manager.dart`

### `vozila` → `v2_vozila` ✅
- `vozila_service.dart`
- `gorivo_service.dart`
- `realtime_manager.dart`

### `pin_zahtevi` → `v2_pin_zahtevi` ✅
- `pin_zahtev_service.dart`
- `registrovani_putnik_service.dart`

### `push_tokens` → `v2_push_tokens` ✅
- `push_token_service.dart`
- `realtime_notification_service.dart`
- `auth_manager.dart`

### `voznje_log` → `v2_statistika_istorija` ✅
- `voznje_log_service.dart` → `v2_statistika_istorija_service.dart` (`V2StatistikaIstorijaService`) ✅
- `v2_finansije_service.dart` (sve .from) ✅
- `statistika_service.dart` (import + klasa) ✅
- `v2_app_settings_service.dart` (import + klasa) ✅
- `realtime_manager.dart` (_loadVlCache) ✅
- `main.dart` (import + dispose) ✅
- `putnik_service.dart` ✅
- `registrovani_putnik_service.dart` ✅ (→ v2_putnik_service.dart)
- `local_notification_service.dart` ✅
- `registrovani_putnik_dialog.dart` ✅ (→ v2_putnik_dialog.dart)

### `seat_requests` → `v2_polasci` ✅
- `v2_seat_request_service.dart` → `v2_polasci_service.dart` (`V2PolasciService`) ✅
- `realtime_manager.dart` (_loadSrCache) ✅
- `kombi_eta_widget.dart` → `v2_kombi_eta_widget.dart` (subscribe + .from) ✅
- `seat_requests_screen.dart` → `v2_polasci_screen.dart` ✅
- `seat_requests_log_screen.dart` → `v2_polasci_log_screen.dart` ✅
- `putnik_service.dart` ✅
- `local_notification_service.dart` ✅
- `v2_home_screen.dart` ✅

---

## SEKCIJA 3 — Kompleksna zamena (arhitektura) ✅

### `registrovani_putnici` → `v2_radnici` / `v2_ucenici` / `v2_dnevni` / `v2_posiljke`

> **Odluka:** Pravi refaktor — svi fajlovi migriraju na V2PutnikService + V2MasterRealtimeManager

| Fajl | Tip | Status |
|---|---|:---:|
| `registrovani_putnik_service.dart` | servis | ✅ → `v2_putnik_service.dart` |
| `putnik_service.dart` | servis | ✅ V2MasterRealtimeManager, V2PolasciService |
| `seat_request_service.dart` | servis | ✅ → `v2_polasci_service.dart` |
| `local_notification_service.dart` | servis | ✅ |
| `notification_navigation_service.dart` | servis | ✅ V2MasterRealtimeManager.getPutnikById() |
| `putnik_push_service.dart` | servis | ✅ V2MasterRealtimeManager.getPutnikById() |
| `realtime_manager.dart` | servis | ✅ _loadRpCache → V2MasterRealtimeManager.getAllPutnici() |
| `registrovani_putnik_login_screen.dart` | screen | ✅ V2PutnikService.getSviAktivni() |
| `registrovani_putnici_screen.dart` | screen | ✅ V2PutnikService, v2_statistika_istorija |
| `vozac_action_log_screen.dart` | screen | ✅ → `v2_vozac_action_log_screen.dart` (obrisan stari) |
| `v2_putnik_dialog.dart` | widget | ✅ V2StatistikaIstorijaService.logGreska() |
| `v2_pin_dialog.dart` | widget | ✅ V2PutnikService.updatePin() |

---

## Napomene

- Stare tabele ostaju u bazi za audit/rollback — kod ih više ne koristi
- `V2MasterRealtimeManager` — **jedini globalni realtime singleton** (zamena za `RealtimeManager`)
- `realtime_manager.dart` zadržan u fajl sistemu ali ga ne koristi nijidan consumer

---

## SEKCIJA 4 — V2MasterRealtimeManager kao globalni singleton ✅

> **Cilj:** `RealtimeManager.instance` potpuno zamenjen sa `V2MasterRealtimeManager.instance` u svim consumer fajlovima

| Fajl | Promene | Status |
|---|---|:---:|
| `putnik_service.dart` | `rm.srCache`→`polasciCache`, `rm.vlCache`→`statistikaCache`, `updateSrCache`→`upsertToCache`, subscribe vozac_raspored→v2_vozac_raspored | ✅ |
| `kombi_eta_widget.dart` → `v2_kombi_eta_widget.dart` | `lokacijeCache`, subscribe vozac_lokacije→v2_vozac_lokacije | ✅ |
| `vozac_screen.dart` → `v2_vozac_screen.dart` | `rasporedCache`, subscribe vozac_raspored→v2_vozac_raspored, vozac_putnik→v2_vozac_putnik | ✅ |
| `vozac_action_log_screen.dart` → `v2_vozac_action_log_screen.dart` | subscribe voznje_log→v2_statistika_istorija | ✅ |
