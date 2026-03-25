-- =====================================================
-- [ARHIVA - VIŠE SE NE KORISTI]
-- =====================================================
-- Ovaj fajl je bio zadužen za sync iz v3_operativna_nedelja u v3_gps_raspored.
--
-- MIGRACIJA ZAVRŠENA:
--   - Tabela v3_gps_raspored je uklonjena iz baze
--   - Trigger fn_v3_sync_operativna_to_gps_raspored je uklonjen
--   - Trigger tr_v3_sync_operativna_to_gps_raspored je uklonjen
--   - Sve GPS kolone su premeštene direktno u v3_operativna_nedelja
--     (vozac_id, nav_bar_type, pickup_lat/lng, polazak_vreme,
--      activation_time, gps_status, notification_sent, route_order, estimated_pickup_time)
--
-- v3_operativna_nedelja je sada jedini izvor istine za GPS podatke.
-- GPS cache (v3GpsRasporedCache) u Flutter appu se gradi lokalno
-- iz v3_operativna_nedelja WHERE vozac_id IS NOT NULL.
--
-- Za SQL funkcije koje šalju push notifikacije videti:
--   supabase/gps_raspored_notifications_cron.sql
-- Za optimizaciju rute videti:
--   supabase/gps_route_optimization.sql
-- =====================================================

-- Skript za uklanjanje (izvršiti jednom ako već nije):
-- DROP TRIGGER IF EXISTS tr_v3_sync_operativna_to_gps_raspored ON public.v3_operativna_nedelja;
-- DROP FUNCTION IF EXISTS public.fn_v3_sync_operativna_to_gps_raspored();
-- DROP TRIGGER IF EXISTS tr_v3_gps_raspored_populate_coordinates ON public.v3_gps_raspored;
-- DROP FUNCTION IF EXISTS public.fn_v3_gps_raspored_populate_coordinates();
-- DROP TABLE IF EXISTS public.v3_gps_raspored;

-- 1) Jednokratni backfill
with slot_unique as (
  select
    r.datum,
    r.grad,
    r.vreme,
    min(r.vozac_id::text)::uuid as vozac_id,
    min(r.nav_bar_type) as nav_bar_type
  from public.v3_gps_raspored r
  where r.aktivno = true
  group by r.datum, r.grad, r.vreme
  having count(distinct r.vozac_id) = 1
),
missing as (
  select
    o.putnik_id,
    o.datum,
    o.grad,
    coalesce(o.vreme, o.dodeljeno_vreme, o.zeljeno_vreme) as vreme,
    o.adresa_id_override
  from public.v3_operativna_nedelja o
  where o.aktivno = true
    and o.status_final = 'odobreno'
    and o.putnik_id is not null
    and coalesce(o.vreme, o.dodeljeno_vreme, o.zeljeno_vreme) is not null
    and not exists (
      select 1
      from public.v3_gps_raspored r
      where r.putnik_id = o.putnik_id
        and r.datum = o.datum
        and r.grad = o.grad
        and r.vreme = coalesce(o.vreme, o.dodeljeno_vreme, o.zeljeno_vreme)
        and r.aktivno = true
    )
)
insert into public.v3_gps_raspored (
  vozac_id,
  putnik_id,
  datum,
  grad,
  vreme,
  nav_bar_type,
  aktivno,
  created_by,
  updated_by,
  adresa_id
)
select
  su.vozac_id,
  m.putnik_id,
  m.datum,
  m.grad,
  m.vreme,
  su.nav_bar_type,
  true,
  'operativna_backfill',
  'operativna_backfill',
  m.adresa_id_override
from missing m
join slot_unique su
  on su.datum = m.datum
 and su.grad = m.grad
 and su.vreme = m.vreme
on conflict (putnik_id, datum, vreme, grad, nav_bar_type)
do update set
  vozac_id = excluded.vozac_id,
  aktivno = true,
  adresa_id = coalesce(excluded.adresa_id, public.v3_gps_raspored.adresa_id),
  updated_at = now(),
  updated_by = 'operativna_backfill';

-- 2) Trajni trigger sync
create or replace function public.fn_v3_sync_operativna_to_gps_raspored()
returns trigger
language plpgsql
security definer
as $$
declare
  new_vreme time;
  old_vreme time;
  resolved_vozac_id uuid;
  resolved_nav_bar_type text;
begin
  new_vreme := coalesce(new.vreme, new.dodeljeno_vreme, new.zeljeno_vreme);
  old_vreme := coalesce(old.vreme, old.dodeljeno_vreme, old.zeljeno_vreme);

  if new.putnik_id is null then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if old.datum is distinct from new.datum
       or old.grad is distinct from new.grad
       or old_vreme is distinct from new_vreme then
      update public.v3_gps_raspored r
         set aktivno = false,
             updated_at = now(),
             updated_by = 'operativna_sync_move'
       where r.putnik_id = old.putnik_id
         and r.datum = old.datum
         and r.grad = old.grad
         and r.vreme = old_vreme
         and r.aktivno = true;
    end if;
  end if;

  if new.aktivno = true and new.status_final = 'odobreno' and new_vreme is not null and new.grad is not null then
    with slot_candidates as (
      select
        r.vozac_id,
        min(r.nav_bar_type) as nav_bar_type
      from public.v3_gps_raspored r
      where r.datum = new.datum
        and r.grad = new.grad
        and r.vreme = new_vreme
        and r.aktivno = true
      group by r.vozac_id
    ),
    slot_unique as (
      select vozac_id, nav_bar_type
      from slot_candidates
      where (select count(*) from slot_candidates) = 1
    )
    select su.vozac_id, su.nav_bar_type
      into resolved_vozac_id, resolved_nav_bar_type
    from slot_unique su
    limit 1;

    if resolved_vozac_id is not null then
      insert into public.v3_gps_raspored (
        vozac_id,
        putnik_id,
        datum,
        grad,
        vreme,
        nav_bar_type,
        aktivno,
        created_by,
        updated_by,
        adresa_id
      ) values (
        resolved_vozac_id,
        new.putnik_id,
        new.datum,
        new.grad,
        new_vreme,
        coalesce(resolved_nav_bar_type, 'zimski'),
        true,
        'operativna_sync',
        'operativna_sync',
        new.adresa_id_override
      )
      on conflict (putnik_id, datum, vreme, grad, nav_bar_type)
      do update set
        vozac_id = excluded.vozac_id,
        aktivno = true,
        adresa_id = coalesce(excluded.adresa_id, public.v3_gps_raspored.adresa_id),
        updated_at = now(),
        updated_by = 'operativna_sync';
    end if;
  else
    if new_vreme is not null then
      update public.v3_gps_raspored r
         set aktivno = false,
             updated_at = now(),
             updated_by = 'operativna_sync_deactivate'
       where r.putnik_id = new.putnik_id
         and r.datum = new.datum
         and r.grad = new.grad
         and r.vreme = new_vreme
         and r.aktivno = true;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists tr_v3_sync_operativna_to_gps_raspored on public.v3_operativna_nedelja;

create trigger tr_v3_sync_operativna_to_gps_raspored
after insert or update of status_final, aktivno, vreme, dodeljeno_vreme, zeljeno_vreme, datum, grad, adresa_id_override
on public.v3_operativna_nedelja
for each row
execute function public.fn_v3_sync_operativna_to_gps_raspored();
