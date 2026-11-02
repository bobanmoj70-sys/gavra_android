-- Dodela (v3_trenutna_dodela) se do sada pravila iskljucivo na klijentu
-- (realtime hook u V3MasterRealtimeManager -> syncTerminDodelaFromSlotForRow).
-- Termini odobreni server-side kronom (process_pending_zahtevi_slots ->
-- transfer_to_operativna_nedelja) dok nijedan klijent nije online nikad ne bi
-- dobili dodelu, pa su nevidljivi za v3_find_termins_for_auto_prepare
-- (INNER JOIN na v3_trenutna_dodela) i tiho ispadali iz optimized_order.
-- Incident 2026-11-02: 3 dnevna putnika + 1 radnik nisu bili u optimizaciji.
--
-- Ovaj trigger radi istu logiku server-side, za svaki INSERT/UPDATE
-- operativnog reda — bez zavisnosti od toga ko slusa realtime.

create or replace function public.fn_v3_operativna_sync_dodela()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_slot_id uuid;
  v_slot_vozac uuid;
begin
  -- Neaktivan/nekonzistentan termin ne sme imati dodelu.
  if new.otkazano_at is not null
     or new.pokupljen_at is not null
     or new.created_by is null
     or new.polazak_at is null then
    delete from public.v3_trenutna_dodela where termin_id = new.id;
    return new;
  end if;

  select s.id, s.vozac_v3_auth_id
    into v_slot_id, v_slot_vozac
    from public.v3_trenutna_dodela_slot s
   where s.datum = new.datum
     and s.grad = new.grad
     and s.vreme = new.polazak_at
   limit 1;

  -- Slot bez vozaca -> nema kome da se dodeli (isto pravilo kao klijentski sync).
  if v_slot_id is null or v_slot_vozac is null then
    delete from public.v3_trenutna_dodela where termin_id = new.id;
    return new;
  end if;

  insert into public.v3_trenutna_dodela (
    termin_id,
    putnik_v3_auth_id,
    vozac_v3_auth_id,
    slot_id,
    updated_by
  ) values (
    new.id,
    new.created_by,
    v_slot_vozac,
    v_slot_id,
    new.updated_by
  )
  on conflict (termin_id) do update
    set slot_id = excluded.slot_id,
        putnik_v3_auth_id = excluded.putnik_v3_auth_id,
        updated_by = excluded.updated_by;
  -- vozac_v3_auth_id se namerno ne prepisuje na konfliktu: "putnik override"
  -- na drugog vozaca (assignPutnikOverride) ostaje ocuvan. Reassign celog
  -- slota ide kroz assignTerminDefault koji svakako brise i ponovo pravi dodele.

  return new;
end;
$$;

drop trigger if exists trg_v3_operativna_sync_dodela on public.v3_operativna_nedelja;
create trigger trg_v3_operativna_sync_dodela
after insert or update on public.v3_operativna_nedelja
for each row execute function public.fn_v3_operativna_sync_dodela();

-- Backfill 1: aktivni termini bez dodele ciji slot ima vozaca (nastali dok
-- nijedan klijent nije bio online).
insert into public.v3_trenutna_dodela (
  termin_id, putnik_v3_auth_id, vozac_v3_auth_id, slot_id, updated_by
)
select o.id, o.created_by, s.vozac_v3_auth_id, s.id, o.updated_by
from public.v3_operativna_nedelja o
join public.v3_trenutna_dodela_slot s
  on s.datum = o.datum
 and s.grad = o.grad
 and s.vreme = o.polazak_at
where o.otkazano_at is null
  and o.pokupljen_at is null
  and o.polazak_at is not null
  and o.created_by is not null
  and s.vozac_v3_auth_id is not null
  and not exists (
    select 1 from public.v3_trenutna_dodela d where d.termin_id = o.id
  );

-- Backfill 2: postojece dodele sa zastarelim/nedostajucim slot_id.
update public.v3_trenutna_dodela d
set slot_id = s.id
from public.v3_operativna_nedelja o
join public.v3_trenutna_dodela_slot s
  on s.datum = o.datum
 and s.grad = o.grad
 and s.vreme = o.polazak_at
where d.termin_id = o.id
  and d.slot_id is distinct from s.id;

-- Backfill 3: ocisti dodele koje su prezivele otkazivanje/pokupljenje
-- (realtime delete nije pouzdan kad niko ne slusa).
delete from public.v3_trenutna_dodela d
using public.v3_operativna_nedelja o
where d.termin_id = o.id
  and (o.otkazano_at is not null or o.pokupljen_at is not null);
