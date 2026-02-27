# Migracija na v2_ tabele — Status

Poslednje ažurirano: 2026-02-27

---

## ✅ KOMPLETNO — SVE MIGRIRANO

### Servisi
| Fajl | Napomena |
|---|---|
| `v2_adresa_supabase_service.dart` | ✅ |
| `v2_app_settings_service.dart` | ✅ |
| `v2_dnevni_service.dart` | ✅ novi |
| `v2_driver_location_service.dart` | ✅ |
| `v2_finansije_service.dart` | ✅ |
| `v2_gorivo_service.dart` | ✅ |
| `v2_kapacitet_service.dart` | ✅ |
| `v2_pin_zahtev_service.dart` | ✅ |
| `v2_polasci_service.dart` | ✅ zamena za seat_request_service + v2_seat_request_service |
| `v2_posiljka_service.dart` | ✅ |
| `v2_push_token_service.dart` | ✅ |
| `v2_putnik_service.dart` | ✅ zamena za registrovani_putnik_service |
| `v2_racun_service.dart` | ✅ |
| `v2_radnik_service.dart` | ✅ novi |
| `v2_statistika_istorija_service.dart` | ✅ zamena za voznje_log_service |
| `v2_ucenik_service.dart` | ✅ novi |
| `v2_vozac_putnik_service.dart` | ✅ |
| `v2_vozac_raspored_service.dart` | ✅ |
| `v2_vozac_service.dart` | ✅ |
| `v2_vozila_service.dart` | ✅ |
| `v2_weather_alert_service.dart` | ✅ |
| `putnik_service.dart` | ✅ migrirano: v2_polasci, v2_statistika_istorija, V2MasterRealtimeManager |
| `local_notification_service.dart` | ✅ migrirano |
| `notification_navigation_service.dart` | ✅ migrirano |
| `putnik_push_service.dart` | ✅ migrirano |

### Infrastruktura
| Fajl | Napomena |
|---|---|
| `realtime/v2_master_realtime_manager.dart` | ✅ JEDINI globalni realtime singleton, 17 cache-ova |
| `realtime/realtime_manager.dart` | ⚠️ Zadržan (nije obrisan) — više ga ne koristi nijidan consumer fajl |
| `main.dart` | ✅ V2MasterRealtimeManager.initialize() |

### Screeni
| Fajl | Napomena |
|---|---|
| `v2_home_screen.dart` | ✅ V2PolasciService umjesto SeatRequestService |
| `v2_polasci_screen.dart` | ✅ V2PolasciService |
| `v2_polasci_log_screen.dart` | ✅ V2PolasciService |
| `registrovani_putnici_screen.dart` | ✅ V2PutnikService, v2_statistika_istorija |
| `registrovani_putnik_login_screen.dart` | ✅ V2PutnikService.getSviAktivni() |
| `v2_vozac_action_log_screen.dart` | ✅ V2MasterRealtimeManager, v2_statistika_istorija (stari vozac_action_log_screen.dart obrisan) |
| `v2_vozac_screen.dart` | ✅ V2MasterRealtimeManager, v2_vozac_raspored, v2_vozac_putnik (preimenovan iz vozac_screen.dart) |

### Widgeti
| Fajl | Napomena |
|---|---|
| `v2_pin_dialog.dart` | ✅ V2PutnikService.updatePin() |
| `v2_putnik_dialog.dart` | ✅ V2StatistikaIstorijaService.logGreska() |
| `v2_kombi_eta_widget.dart` | ✅ V2MasterRealtimeManager, v2_vozac_lokacije (preimenovan iz kombi_eta_widget.dart) |

---

## Napomene

- Sve stare tabele (`seat_requests`, `voznje_log`, `registrovani_putnici`) više se ne koriste u kodu
- `V2MasterRealtimeManager` je **jedini globalni realtime singleton** — `RealtimeManager` više ga ne koristi nijidan consumer fajl
- `V2PolasciService` je jedini servis za polazak operacije
- `V2StatistikaIstorijaService` je jedini log servis
- `V2PutnikService` je jedini servis za CRUD putnika

### Preimenovani fajlovi (v2 migracija)
| Staro ime | Novo ime |
|---|---|
| `kombi_eta_widget.dart` | `v2_kombi_eta_widget.dart` |
| `vozac_screen.dart` | `v2_vozac_screen.dart` |
| `vozac_action_log_screen.dart` | obrisano — postoji `v2_vozac_action_log_screen.dart` |
