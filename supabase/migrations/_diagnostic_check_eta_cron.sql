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

-- 5. Da li ijedan slot ima dodeljene putnike i/ili optimized_order?
select s.id, s.grad, s.vreme, s.datum,
       count(d.putnik_id) as passenger_count,
       array_length(s.optimized_order, 1) as optimized_order_length
from v3_trenutna_dodela_slot s
left join v3_trenutna_dodela d on d.slot_id = s.id
group by s.id, s.grad, s.vreme, s.datum, s.optimized_order
order by s.created_at desc
limit 20;
