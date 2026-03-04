# Plan: v2_polasci kao operativna tabela + v2_statistika_istorija kao arhiva

Poslednje ažuriranje: 2026-03-04

---

## Faza 4 — Pazar iz v2_polasci ✅ URAĐENO (2026-03-04)

### Nova kolona
```sql
ALTER TABLE public.v2_polasci ADD COLUMN placen_tip text DEFAULT NULL;
-- vrijednosti: 'dnevna' | 'mesecna'
```

### Logika
- Dnevna uplata → `v2OznaciPlaceno()` upisuje `placen_tip='dnevna'` u `v2_polasci`
- Mesečna uplata → `upisPlacanjaULog()` upisuje `placen_tip='mesecna'` u `v2_polasci` (po `putnik_id`)
- Oba slučaja i dalje INSERT-uju u `v2_statistika_istorija` (arhiva ostaje)

### Pazar stream
- Tekući dan: `_pazarIzPolasciCache()` — čita `polasciCache` direktno, **0 DB upita, realtime**
- Prošli datumi: i dalje DB upit na `v2_statistika_istorija`

---

## Cilj

- `v2_polasci` = jedini izvor istine za **tekući dan** (operativna tabela)
- `v2_statistika_istorija` = **arhiva** svih akcija, čita se samo na zahtev
- Eliminisati `_buildPutnik()` join između dva cache-a
- Isključiti Realtime na `v2_statistika_istorija` (append-only, ne treba live)

---

## Faza 1 — Dodavanje dnevnih kolona u v2_polasci ✅ URAĐENO (2026-03-03)

### Nove kolone u bazi

```sql
ALTER TABLE public.v2_polasci
  ADD COLUMN datum_akcije     date        DEFAULT NULL,  -- kada su dnevne akcije upisane
  ADD COLUMN pokupljen_datum  date        DEFAULT NULL,  -- datum kada je pokupljen (reset kontrola)
  ADD COLUMN placen           boolean     DEFAULT false, -- plaćen danas
  ADD COLUMN placen_iznos     numeric     DEFAULT NULL,  -- iznos plaćanja
  ADD COLUMN placen_vozac_id  uuid        DEFAULT NULL,  -- ko je naplatio (uuid)
  ADD COLUMN placen_vozac_ime text        DEFAULT NULL;  -- ko je naplatio (ime, denormalizovano)
```

### Logika reset kontrole
- `datum_akcije` = datum kada su `placen`, `pokupljen_datum` upisani
- Sledeći dan: ako `datum_akcije != today` → dnevne kolone se ignorišu (stari podaci)
- Reset se radi **tek kad vozači završe voznje** (Faza 2)

---

## Faza 2 — Reset trigger + migracija u arhivu ✅ URAĐENO (manuelno u kodu)

### Šta treba uraditi

1. **PostgreSQL funkcija** `v2_reset_dnevnih_polazaka()`:
   - Prolazi kroz sve redove gde `datum_akcije < today`
   - Za svaki red koji ima `placen=true` ili `pokupljen_datum IS NOT NULL`:
     - Proverava da li već postoji u `v2_statistika_istorija` (duplikat check)
     - Ako ne postoji → INSERT u `v2_statistika_istorija`
   - Reset: `placen=false`, `placen_iznos=null`, `placen_vozac_id=null`, `placen_vozac_ime=null`, `pokupljen_datum=null`, `datum_akcije=null`

2. **Supabase scheduled job** (pg_cron) — okida `v2_reset_dnevnih_polazaka()` svaki dan u **04:00**

3. **Alternativa bez pg_cron**: Reset se okida iz app-a pri startu novog dana (već postoji `refreshForNewDay()` u `V2MasterRealtimeManager`)

---

## Faza 3 — Dart izmene ✅ URAĐENO (2026-03-04)

### Izmene u kodu

| Fajl | Izmena |
|---|---|
| `v2_polasci_service.dart` — `v2OznaciPokupljen()` | Pišu `pokupljen_datum=today`, `datum_akcije=today` u `v2_polasci` + INSERT u statistika kao i sada | ✅ |
| `v2_polasci_service.dart` — `v2OznaciPlaceno()` | Pišu `placen=true`, `placen_iznos`, `placen_vozac_id/ime`, `datum_akcije=today` direktno u `v2_polasci` | ✅ |
| `v2_polasci_service.dart` — `_buildPutnik()` | Čita `placen`, `placen_iznos`, `pokupljen_datum` direktno sa `srRow` — **nema više `matchedVl` joina**, uklonjen `vlRows` parametar | ✅ |
| `v2_master_realtime_manager.dart` | `statistikaCache` se više ne puni pri startu — `loadStatistikaCache()` je sada javna, poziva se lazy (pazar, profil, lista) | ✅ |
| `v2_statistika_service.dart` — `subscribe('v2_statistika_istorija')` | **Uklonjeno** iz inicijalizacije — zamena: lazy load on-demand | ✅ |

### Benefiti nakon Faze 3
- `_buildPutnik()` = 0 join operacija, sve sa jednog reda
- `statistikaCache` se može ukloniti iz startup load-a (manje memorije, brži start)
- Realtime na `v2_statistika_istorija` = OFF (ušteda na concurrent connections)

---

## Status Realtime channels

| Tabela | Realtime | Napomena |
|---|---|---|
| `v2_polasci` | ✅ ON | Operativna — mora biti živo |
| `v2_vozac_lokacije` | ✅ ON | GPS — mora biti živo |
| `v2_pin_zahtevi` | ✅ ON | Dispečer mora videti odmah |
| `v2_vozac_putnik` | ✅ ON | Vozač vidi listu živo |
| `v2_vozac_raspored` | ✅ ON | Vozač vidi raspored živo |
| `v2_radnici` | ✅ OFF (2026-03-03) | Samo admin ekran, retko se menja |
| `v2_ucenici` | ✅ OFF (2026-03-03) | Samo admin ekran, retko se menja |
| `v2_dnevni` | ✅ OFF (2026-03-03) | Samo admin ekran, retko se menja |
| `v2_posiljke` | ✅ OFF (2026-03-03) | Samo admin ekran, retko se menja |
| `v2_statistika_istorija` | ✅ OFF (2026-03-03) | Arhiva — pazar/lista se ne osvežava automatski, rešava Faza 3 |
| `v2_vozaci` | ✅ OFF (2026-03-03) | Statički |
| `v2_vozila` | ✅ OFF (2026-03-03) | Statički |
| `v2_adrese` | ✅ OFF (2026-03-03) | Statički |
| `v2_kapacitet_polazaka` | ✅ OFF (2026-03-03) | Statički |
| `v2_finansije_troskovi` | ✅ OFF (2026-03-03) | Statički |
| `v2_pumpa_config` | ✅ OFF (2026-03-03) | Statički |
| `v2_app_settings` | ✅ OFF (2026-03-03) | Statički |

---

## Realtime publikacija — finalno stanje (2026-03-03)

Samo 5 tabela u `supabase_realtime` publikaciji:
- `v2_polasci` — operativna
- `v2_vozac_lokacije` — GPS
- `v2_pin_zahtevi` — dispečer
- `v2_vozac_putnik` — vozač
- `v2_vozac_raspored` — vozač

Sve ostale tabele (22) su van publikacije — nema Realtime troškova.

---

## select() problemi (filter u kodu umesto na bazi)

| Lokacija | Problem | Status |
|---|---|---|
| `v2_master_realtime_manager.dart` — `findByTelefon()` DB fallback | `select()` sa nepostojećim kolonama (prezime, adresa, tip, aktivan) → zamenjeno ispravnim kolonama | ✅ Urađeno (2026-03-04) |
| `v2_putnik_statistike_helper.dart` — 3 metode | `select()` već ima eksplicitne kolone `'id, tip, datum, iznos, broj_mesta, created_at'` | ✅ Već ispravno |
