# 🚗 DISPECER CRON JOB - Live stanje baze

Ovo je dokumentacija za stvarno stanje u Supabase bazi, ne samo za repo fajl.

## Šta je trenutno u bazi

Pronađeno je sledeće:

- `set_zahtev_scheduled_at()` - trigger funkcija koja postavlja `scheduled_at`
- `fn_v3_dispatcher()` - trigger na `v3_zahtevi`
- `process_pending_zahtevi_slots()` - glavni slots-based procesor
- `process_pending_zahtevi_v2()` - starija verzija procesora
- `process_pending_zahtevi_final()` - još jedna verzija procesora
- `cron.job` sadrži job `simple-dispatcher` koji trenutno radi direktan `UPDATE`

## Važan problem

Trenutni cron job u bazi je previše jednostavan:

```sql
UPDATE v3_zahtevi
SET status = 'odobreno', dodeljeno_vreme = zeljeno_vreme
WHERE status = 'obrada' AND aktivno = true AND scheduled_at <= NOW();
```

To znači da **preskače kapacitet logiku** i ne koristi slots proveru.

## Šta treba koristiti

Preporuka je da cron poziva:

```sql
SELECT * FROM public.process_pending_zahtevi();
```

Repo fajl `supabase/dispecer_cron.sql` sada pravi wrapper koji zove:

```sql
SELECT * FROM public.process_pending_zahtevi_slots();
```

## Kako proveriti trenutno stanje

```sql
SELECT * FROM cron.job ORDER BY jobid;
SELECT * FROM public.get_pending_zahtevi_status();
SELECT * FROM v3_zahtevi WHERE status = 'obrada' AND aktivno = true ORDER BY scheduled_at;
```

## Kako popraviti cron

Pokreni sadržaj iz `supabase/dispecer_cron.sql` u Supabase SQL Editor-u.

To će:

- dodati kompatibilne wrapper funkcije
- ukinuti `simple-dispatcher`
- napraviti novi job `dispecer-slots`
- usmeriti obradu na slots logiku

## Manuelno testiranje

```sql
SELECT * FROM public.manual_process_zahtevi();
```

## Bitno za tebe

Ako želiš da aplikacija radi po pravilima koja si opisao, **ne smeš ostaviti stari cron job** koji direktno odobrava zahteve.

---
*Ažurirano: 2026-03-22*