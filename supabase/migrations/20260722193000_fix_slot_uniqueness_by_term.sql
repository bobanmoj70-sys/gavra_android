-- Ispravka logike slota:
-- Slot mora biti jedinstven po terminu (datum, grad, vreme),
-- a promena vozača treba da prepiše postojeći slot umesto pravljenja duplikata.

-- 1) Odredi kanonski slot po (datum, grad, vreme):
--    prioritet je slot koji je već referenciran iz v3_trenutna_dodela,
--    zatim noviji updated_at/created_at.
with slot_ref as (
  select slot_id, count(*)::int as ref_count
  from public.v3_trenutna_dodela
  where slot_id is not null
  group by slot_id
), ranked as (
  select
    s.id,
    s.datum,
    s.grad,
    s.vreme,
    coalesce(sr.ref_count, 0) as ref_count,
    s.updated_at,
    s.created_at,
    row_number() over (
      partition by s.datum, s.grad, s.vreme
      order by
        (coalesce(sr.ref_count, 0) > 0) desc,
        coalesce(sr.ref_count, 0) desc,
        s.updated_at desc nulls last,
        s.created_at desc nulls last,
        s.id desc
    ) as rn
  from public.v3_trenutna_dodela_slot s
  left join slot_ref sr on sr.slot_id = s.id
), canonical as (
  select datum, grad, vreme, id as keep_id
  from ranked
  where rn = 1
), duplicates as (
  select r.id as drop_id, c.keep_id
  from ranked r
  join canonical c using (datum, grad, vreme)
  where r.rn > 1
)
-- 2) Preveži sve reference ka kanonskom slot_id.
update public.v3_trenutna_dodela td
set slot_id = d.keep_id,
    updated_at = now()
from duplicates d
where td.slot_id = d.drop_id;

-- 3) Ako kanonski slot nema waypoints_json, preuzmi iz nekog duplikata koji ga ima.
with slot_ref as (
  select slot_id, count(*)::int as ref_count
  from public.v3_trenutna_dodela
  where slot_id is not null
  group by slot_id
), ranked as (
  select
    s.id,
    s.datum,
    s.grad,
    s.vreme,
    coalesce(sr.ref_count, 0) as ref_count,
    s.updated_at,
    s.created_at,
    row_number() over (
      partition by s.datum, s.grad, s.vreme
      order by
        (coalesce(sr.ref_count, 0) > 0) desc,
        coalesce(sr.ref_count, 0) desc,
        s.updated_at desc nulls last,
        s.created_at desc nulls last,
        s.id desc
    ) as rn
  from public.v3_trenutna_dodela_slot s
  left join slot_ref sr on sr.slot_id = s.id
), canonical as (
  select datum, grad, vreme, id as keep_id
  from ranked
  where rn = 1
), duplicates as (
  select r.id as drop_id, c.keep_id
  from ranked r
  join canonical c using (datum, grad, vreme)
  where r.rn > 1
)
update public.v3_trenutna_dodela_slot k
set waypoints_json = dslot.waypoints_json,
    updated_at = now()
from duplicates d
join public.v3_trenutna_dodela_slot dslot on dslot.id = d.drop_id
where k.id = d.keep_id
  and (k.waypoints_json is null or k.waypoints_json = '{}'::jsonb)
  and dslot.waypoints_json is not null
  and dslot.waypoints_json <> '{}'::jsonb;

-- 4) Obriši duplikate slotova nakon prevezivanja.
with slot_ref as (
  select slot_id, count(*)::int as ref_count
  from public.v3_trenutna_dodela
  where slot_id is not null
  group by slot_id
), ranked as (
  select
    s.id,
    s.datum,
    s.grad,
    s.vreme,
    coalesce(sr.ref_count, 0) as ref_count,
    s.updated_at,
    s.created_at,
    row_number() over (
      partition by s.datum, s.grad, s.vreme
      order by
        (coalesce(sr.ref_count, 0) > 0) desc,
        coalesce(sr.ref_count, 0) desc,
        s.updated_at desc nulls last,
        s.created_at desc nulls last,
        s.id desc
    ) as rn
  from public.v3_trenutna_dodela_slot s
  left join slot_ref sr on sr.slot_id = s.id
)
delete from public.v3_trenutna_dodela_slot s
using ranked r
where s.id = r.id
  and r.rn > 1;

-- 5) Zameni pogrešan unique ključ sa ispravnim po terminu.
alter table public.v3_trenutna_dodela_slot
  drop constraint if exists v3_trenutna_dodela_slot_unique;

alter table public.v3_trenutna_dodela_slot
  add constraint v3_trenutna_dodela_slot_unique_slot unique (datum, grad, vreme);
