# 🚗 DISPECER WAKE-ONLY - Live stanje baze

Ovo je dokumentacija za trenutno, usklađeno stanje u Supabase bazi.

## Aktivni tok

- `tr_v3_dispatcher` na `public.v3_zahtevi` poziva `fn_v3_dispatcher()`.
- `fn_v3_dispatcher()` postavlja `scheduled_at` po poslovnim pravilima i šalje `pg_notify('dispatcher_wake', ...)`.
- Obrada ide kroz `process_pending_zahtevi()` -> `process_pending_zahtevi_slots()`.

## Šta je uklonjeno

- Nema `simple-dispatcher` cron job-a.
- Nema `dispecer-slots` cron job-a.
- Nema `tr_v3_wake_dispecer_cron` i `wake_dispecer_cron_on_zahtev()`.
- Nema `ensure_dispecer_cron_running()`.

## Kako proveriti stanje

```sql
SELECT jobid, jobname, schedule, command
FROM cron.job
WHERE jobname IN ('simple-dispatcher', 'dispecer-slots');

SELECT t.tgname, p.proname AS function_name, pg_get_triggerdef(t.oid) AS trigger_def
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_proc p ON p.oid = t.tgfoid
WHERE n.nspname = 'public'
	AND c.relname = 'v3_zahtevi'
	AND NOT t.tgisinternal
ORDER BY t.tgname;

SELECT *
FROM public.v3_zahtevi
WHERE status = 'obrada' AND aktivno = true
ORDER BY scheduled_at;
```

## Napomena

Model je wake-only: nema periodičnog cron dispatcher procesa.

---
*Ažurirano: 2026-03-23*