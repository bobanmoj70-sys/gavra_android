-- Dnevni prosek potrošnje goriva po radnim danima (pon–pet).
-- Ukupna potrošnja (bez source='inicijalni_import' baseline-a) deli se sa
-- brojem radnih dana (pon–pet) od prvog evidentiranog sipanja/potrošnje do
-- danas — uključujući i radne dane bez zapisa. Sve u Europe/Belgrade (DST-safe).
create or replace function public.v3_gorivo_dnevni_prosek()
returns table(prosek_litri numeric, radnih_dana integer, ukupno_litri numeric)
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
    select coalesce(sum(litri), 0) as litri
    from public.v3_gorivo_istorija
    where vrsta = 'potrosnja'
      and coalesce(source, '') <> 'inicijalni_import'
  )
  select case when count(d.dan) = 0 then 0
              else round((select litri from ukupno) / count(d.dan), 1)
         end,
         count(d.dan)::integer,
         (select litri from ukupno)
  from dani d
  where extract(isodow from d.dan) between 1 and 5;
$$;
