# 🚗 DISPECER CRON JOB - Automatska obrada zahteva

Automatski sistem za obradu putničkih zahteva prema definisanim pravilima čekanja.

## 📋 Pregled sistema

Dispecer cron job automatski procesira zahteve iz `v3_zahtevi` tabele i primenjuje sledeća pravila:

| Tip putnika | Grad | Uslov | Čekanje | Provera kapaciteta |
|-------------|------|-------|---------|-------------------|
| **Učenik** | BC | za sutra, do 16h | ⏱️ **5 min** | ❌ Garantovano |
| **Učenik** | BC | za sutra, posle 16h | ⏱️ **10 min** | ✅ Da |
| **Radnik** | BC | — | ⏱️ **5 min** | ✅ Da |
| **Učenik/Radnik** | VS | — | ⏱️ **10 min** | ✅ Da |
| **Pošiljka** | bilo koji | — | ⏱️ **10 min** | ❌ Ne zauzima mesta |
| **Dnevni** | bilo koji | — | ♾️ **nikad auto** | 🔐 Admin ručno |

## 🔧 Instalacija

### 1. Pokreni SQL skriptu u Supabase

```sql
-- Kopiraj i pokreni sadržaj iz: supabase/dispecer_cron.sql
-- Ovo će kreirati sve potrebne funkcije i trigger-e
```

### 2. Aktiviraj pg_cron extension

```sql
-- U Supabase SQL Editor (potrebne admin privilegije):
CREATE EXTENSION IF NOT EXISTS pg_cron;
```

### 3. Setup cron job

```sql
-- Pokreni dispecer svakih 3 minuta:
SELECT cron.schedule(
    'dispecer-auto-process',
    '*/3 * * * *', 
    'SELECT * FROM process_pending_zahtevi();'
);
```

## 🎮 Korišćenje

### Manuelno pokretanje
```sql
-- Pokreni obradu odmah (za testiranje):
SELECT * FROM manual_process_zahtevi();
```

### Pregled pending zahteva
```sql
-- Vidi koji zahtevi čekaju obradu:
SELECT * FROM get_pending_zahtevi_status();
```

### Monitoring cron job-ova
```sql
-- Pregled svih cron job-ova:
SELECT * FROM cron.job;

-- Pregled logova:
SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;
```

## 🔄 Kako funkcioniše

### 1. Novi zahtev stiže
- Putnik šalje zahtev kroz aplikaciju
- **Trigger automatski postavlja `scheduled_at`** timestamp na osnovu dispecer pravila
- Zahtev dobija status `'obrada'`

### 2. Cron job procesira
- Svakih 3 minuta pokreće se `process_pending_zahtevi()`
- Uzima sve zahteve gde je `scheduled_at <= NOW()`
- Primenjuje dispecer pravila za svaki tip putnika

### 3. Rezultat obrade
- **ODOBRENO**: Kreira se termin u `v3_gps_raspored` tabeli
- **ALTERNATIVA**: Ponuđuje vremena ±15 min od željenog

## 📊 Rezultati funkcije

```sql
-- process_pending_zahtevi() vraća:
{
  "processed_count": 5,     -- Ukupno obrađeno zahteva  
  "approved_count": 3,      -- Odobreno direktno
  "alternative_count": 2,   -- Ponuđena alternativa
  "log_message": "Obrađeno 5 zahteva - 3 odobreno, 2 alternativa"
}
```

## ⚙️ Konfiguracija

### Promena intervala cron job-a
```sql
-- Za češće pokretanje (svakih 2 minuta):
SELECT cron.unschedule('dispecer-auto-process');
SELECT cron.schedule('dispecer-auto-process', '*/2 * * * *', 'SELECT * FROM process_pending_zahtevi();');
```

### Promena kapaciteta vozila
```sql
-- U funkciji process_pending_zahtevi(), menjaj:
IF existing_count >= 8 THEN  -- <- Ovde menjaj broj mesta
    should_approve := false;
END IF;
```

### Promena pravila čekanja
```sql
-- U funkciji set_zahtev_process_after(), menjaj:
cekanje_minuta := 5;  -- <- Nova vrednost u minutima
```

## 🚨 Troubleshooting

### Cron job se ne pokreće
```sql
-- Proveri da li je extension aktiviran:
SELECT * FROM pg_extension WHERE extname = 'pg_cron';

-- Proveri cron job status:
SELECT * FROM cron.job WHERE jobname = 'dispecer-auto-process';
```

### Zahtevi se ne obrađuju
```sql
-- Proveri pending zahteve:
SELECT * FROM get_pending_zahtevi_status();

-- Manuelno pokreni obradu:
SELECT * FROM manual_process_zahtevi();
```

### Greške u logovima
```sql
-- Pregled error logova:
SELECT * FROM cron.job_run_details 
WHERE status = 'failed' 
ORDER BY start_time DESC LIMIT 5;
```

## 🔒 Bezbednost

- Funkcije koriste `SECURITY DEFINER` - pokreću se sa privilegijama vlasnika
- Svi updates prate `updated_by = 'dispecer_cron'` za audit trail
- Trigger automatski postavlja `scheduled_at` - nema manuelnog mešanja

## 📈 Performance

- Cron job procesira samo zahteve gde je `scheduled_at <= NOW()`
- Koristi indexe na `status`, `aktivno` i `scheduled_at` kolone
- Minimal impact - obično obrađuje 0-20 zahteva po pokretanju

## 🎯 Sledeći koraci

1. **Monitoring dashboard** - Kreiranje admin panela za praćenje
2. **Push notifikacije** - Slanje obaveštenja putnicima o rezultatu
3. **Napredna optimizacija** - AI-based predlog termina
4. **Analytics** - Statistike uspešnosti automatske obrade

---
*Kreiran: 2026-03-22 | Verzija: 1.0 | Autor: GitHub Copilot*