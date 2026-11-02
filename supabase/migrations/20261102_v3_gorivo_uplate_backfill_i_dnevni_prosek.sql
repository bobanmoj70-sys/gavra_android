-- Dnevni prosek uplata za gorivo (RSD):
-- 1) Backfill: uplate evidentirane kao troškovi (v3_finansije, tip='rashod',
--    kategorija='gorivo') pre nego što je trigger počeo da piše 'uplata' redove
--    u v3_gorivo_istorija dobijaju svoj istorijski red (source='backfill_finansije',
--    originalni created_at). Granica je prvi postojeći 'uplata' red, odnosno
--    2026-10-31 (migracija koja je uvela logovanje uplata).
-- 2) RPC v3_gorivo_dnevni_prosek_uplata: suma uplata ÷ radni dani (pon–pet),
--    isti imenilac kao v3_gorivo_dnevni_prosek (litri) da bi proseci bili uporedivi.

insert into public.v3_gorivo_istorija
  (gorivo_id, vrsta, litri, dug_promena, napomena, source, created_at)
select
  (select id::text from public.v3_gorivo limit 1),
  'uplata',
  0,
  f.iznos,
  coalesce(nullif(trim(f.naziv), ''), 'Uplata za gorivo'),
  'backfill_finansije',
  f.created_at
from public.v3_finansije f
where f.tip = 'rashod'
  and f.kategorija = 'gorivo'
  and f.iznos > 0
  and f.created_at < coalesce(
    (select min(i.created_at) from public.v3_gorivo_istorija i where i.vrsta = 'uplata'),
    timestamptz '2026-10-31 00:00:00+02'
  )
  and not exists (
    select 1
    from public.v3_gorivo_istorija i
    where i.vrsta = 'uplata'
      and i.source = 'backfill_finansije'
      and i.created_at = f.created_at
      and i.dug_promena = f.iznos
  );

-- Dnevni prosek uplata za gorivo po radnim danima (pon–pet).
-- Ukupne uplate (sve vrste 'uplata' redova, uključujući backfill) dele se sa
-- brojem radnih dana od prvog evidentiranog sipanja/potrošnje do danas —
-- identičan imenilac kao v3_gorivo_dnevni_prosek. Sve u Europe/Belgrade.
create or replace function public.v3_gorivo_dnevni_prosek_uplata()
returns table(prosek_rsd numeric, radnih_dana integer, ukupno_rsd numeric)
language sql
stable
set search_path to 'public'
as $$
  with granice as (
    select (min(created_at) at time zone 'Europe/Belgrade')::date as prvi_dan
    from public.v3_gorivo_istorija
    where vrsta in ('potrosnja', 'dopuna')
      and coalesce(source, '') <> 'inicijalni_import'
  ),
  dani as (
    select generate_series(
      (select prvi_dan from granice),
      (now() at time zone 'Europe/Belgrade')::date,
      interval '1 day'
    )::date as dan
  ),
  ukupno as (
    select coalesce(sum(dug_promena), 0) as rsd
    from public.v3_gorivo_istorija
    where vrsta = 'uplata'
  )
  select case when count(d.dan) = 0 then 0
              else round((select rsd from ukupno) / count(d.dan), 2)
         end,
         count(d.dan)::integer,
         (select rsd from ukupno)
  from dani d
  where extract(isodow from d.dan) between 1 and 5;
$$;
