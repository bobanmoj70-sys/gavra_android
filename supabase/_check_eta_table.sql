-- Pokreni ručno u Supabase SQL Editoru, pošalji mi ceo output

-- 1. Da li kolona slot_id uopšte postoji na tabeli?
select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'v3_eta_results'
order by ordinal_position;

-- 2. Koji unique/exclusion constraint-i trenutno postoje na tabeli?
select conname, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid = 'public.v3_eta_results'::regclass;

-- 3. Da li ima ijedan red ikada upisan u tabelu?
select count(*) as total_rows from public.v3_eta_results;

-- 4. Da li waypoints_json.passengers ima podataka (preduslov za upis)?
select id, grad, vreme, datum,
       jsonb_array_length(coalesce(waypoints_json->'passengers','[]'::jsonb)) as passenger_count
from v3_trenutna_dodela_slot
order by created_at desc
limit 10;
