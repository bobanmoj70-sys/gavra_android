-- DIJAGNOSTIKA (nije prava migracija — pokreni ručno u SQL Editoru i pošalji rezultat)
-- 1. Da li su ekstenzije uključene?
select extname, extversion from pg_extension where extname in ('pg_cron','pg_net');

-- 2. Da li cron job postoji i kad je poslednji put pokrenut?
select jobid, jobname, schedule, active from cron.job where jobname = 'v3-auto-prepare-termins';

-- 3. Istorija poslednjih pokretanja (ako job postoji)
select jobid, status, return_message, start_time, end_time
from cron.job_run_details
where jobid = (select jobid from cron.job where jobname = 'v3-auto-prepare-termins')
order by start_time desc
limit 10;

-- 4. Da li vault secreti postoje?
select name, created_at, updated_at from vault.decrypted_secrets where name in ('supabase_url','supabase_anon_key');

-- 5. Da li ijedan slot ima popunjen waypoints_json.passengers?
select id, grad, vreme, datum, jsonb_array_length(coalesce(waypoints_json->'passengers','[]'::jsonb)) as passenger_count
from v3_trenutna_dodela_slot
order by created_at desc
limit 20;
