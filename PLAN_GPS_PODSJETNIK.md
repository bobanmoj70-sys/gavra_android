# Plan: GPS Podsjetnik za Vozača

## Cilj
Push notifikacija vozaču (od admina ili automatski) koja kad se klikne
otvori V2VozacScreen i automatski pokrene optimizaciju rute —
kao da je vozač sam kliknuo bijelo dugme.

---

## Šta se NE mijenja
- Putnici dobijaju notifikacije na postojeći način (nije dio ovog plana)
- GPS se ne pokreće automatski — vozač mora kliknuti zeleno START dugme

---

## Flutter — 3 mjesta

### 1. `lib/screens/v2_vozac_screen.dart`
- Dodati parametar `autoOptimize: bool = false`
- Nakon `_initAsync()` ako je `autoOptimize: true` → automatski pokreni `_optimizeCurrentRoute()`

### 2. `lib/services/v2_notification_navigation_service.dart`
- Funkcija `navigateToVozacScreen()` već postoji
- Dodati `autoOptimize: true` pri pozivu V2VozacScreen

### 3. `lib/services/v2_local_notification_service.dart`
- U `handleNotificationTap()` dodati novi type: `'gps_podsjetnik'`
- Kada type == 'gps_podsjetnik' → pozovi `navigateToVozacScreen(autoOptimize: true)`

---

## Backend — 2 opcije (birati jednu ili oboje)

### Opcija A — Admin ručno šalje
- Dugme u admin ekranu pored vozačevog imena
- Šalje push na vozačev token sa `data: { type: 'gps_podsjetnik' }`

### Opcija B — Automatski cron
- Supabase `pg_cron` — šalje push **20 minuta prije polaska**
- Primjer: BC 05:00 → push u 04:40
- Uslov: vozač ima putnike za danas (`v2_vozac_putnik`), a nije još aktivan (`v2_vozac_lokacije.aktivan = false`)
- Poruka: 🚌 *"Za 20 minuta polaziš — BC 05:00. Klikni da pokreneš tracking."*
- Vremenska zona: Srbija UTC+1 (zima) / UTC+2 (ljeto) — cron se podešava u UTC
- Ako dva vozača voze isti termin (npr. cet BC 07:00) — cron pronađe **oba** iz `v2_vozac_putnik` i pošalje push svakome
- `v2_vozac_putnik` je ispravniji izvor (ne `v2_vozac_raspored`) jer tačno zna koji vozač ima koje putnike

---

## Redosljed implementacije
1. Flutter (3 mjesta)
2. Backend opcija A (admin dugme) — jednostavnije
3. Backend opcija B (cron) — opciono, ako treba automatizacija

---

## Status
- [ ] v2_vozac_screen.dart — autoOptimize parametar
- [ ] v2_notification_navigation_service.dart — navigateToVozacScreen sa autoOptimize
- [ ] v2_local_notification_service.dart — type 'gps_podsjetnik'
- [ ] Admin dugme u ekranu
- [ ] Supabase cron (opciono)
