-- Evidencija duga za gorivo u v3_gorivo_istorija:
-- 1) 'uplata' je dozvoljena vrsta (do sad je CHECK blokirao upis uplata)
-- 2) dopuna red dobija dug_promena = koliko je porastao dug tim sipanjem
--    (litri × cena ili ručno unet iznos — šta god da je upisano u dug_iznos)
-- 3) pad dug_iznos (uplata iz dopuna sheeta ili iz Finansija) upisuje 'uplata' red
-- 4) rast dug_iznos bez dopune (ručna izmena) upisuje 'korekcija' red
-- 5) backfill: postojeće dopune dobijaju dug_promena = litri × cena_po_litru

alter table public.v3_gorivo_istorija
  drop constraint if exists v3_gorivo_istorija_vrsta_check;

alter table public.v3_gorivo_istorija
  add constraint v3_gorivo_istorija_vrsta_check
  check (vrsta in ('potrosnja', 'dopuna', 'korekcija', 'uplata'));

comment on column public.v3_gorivo_istorija.dug_promena is
  'Iznos promene duga (RSD): rast duga za dopunu/korekciju, iznos uplate za uplatu.';
comment on column public.v3_gorivo_istorija.vrsta is
  'potrosnja | dopuna | korekcija | uplata';

create or replace function public.v3_gorivo_log_delta_history()
returns trigger
language plpgsql
set search_path to 'public'
as $$
declare
  potrosnja_delta numeric(12,3) := 0;
  dopuna_delta numeric(12,3) := 0;
  dug_delta numeric(12,2) := 0;
  brojac_porastao boolean;
begin
  brojac_porastao :=
    coalesce(new.brojac_pistolj_litri, 0) > coalesce(old.brojac_pistolj_litri, 0);
  dug_delta :=
    coalesce(new.dug_iznos, 0) - coalesce(old.dug_iznos, 0);

  -- AFTER trigger vidi NEW posle BEFORE (delta tanka od brojača već primenjena).
  if brojac_porastao then
    potrosnja_delta := greatest(
      coalesce(old.trenutno_stanje_litri, 0) - coalesce(new.trenutno_stanje_litri, 0),
      0
    );
  elsif new.brojac_pistolj_litri is not distinct from old.brojac_pistolj_litri then
    dopuna_delta := greatest(
      coalesce(new.trenutno_stanje_litri, 0) - coalesce(old.trenutno_stanje_litri, 0),
      0
    );
  end if;

  if potrosnja_delta > 0 then
    insert into public.v3_gorivo_istorija (gorivo_id, vrsta, litri, source)
    values (new.id::text, 'potrosnja', potrosnja_delta, 'brojac_delta');
  end if;

  if dopuna_delta > 0 then
    -- dug_promena = koliko je to sipanje dodalo na dug (može biti null ako je
    -- dopuna bez duga, npr. korekcija stanja naviše)
    insert into public.v3_gorivo_istorija
      (gorivo_id, vrsta, litri, cena_po_litru, dug_promena, source)
    values (
      new.id::text,
      'dopuna',
      dopuna_delta,
      nullif(new.cena_po_litru, 0),
      nullif(greatest(dug_delta, 0), 0),
      'rezervoar_plus'
    );
  end if;

  if dug_delta < 0 then
    -- Uplata: i veća od vrednosti sipanja — skida se sa ukupnog duga.
    insert into public.v3_gorivo_istorija
      (gorivo_id, vrsta, litri, dug_promena, source)
    values (new.id::text, 'uplata', 0, -dug_delta, 'dug_delta');
  elsif dug_delta > 0 and dopuna_delta <= 0 then
    -- Dug povećan bez dopune (ručna izmena u edit sheetu i sl.)
    insert into public.v3_gorivo_istorija
      (gorivo_id, vrsta, litri, dug_promena, source)
    values (new.id::text, 'korekcija', 0, dug_delta, 'dug_delta');
  end if;

  return new;
end;
$$;

comment on function public.v3_gorivo_log_delta_history() is
  'Log potrošnje (pad rezervoara pri porastu brojača), dopune (rast rezervoara + dug koji je dodat), uplata (pad duga) i korekcija duga (rast duga bez dopune).';

drop trigger if exists trg_v3_gorivo_log_delta_history on public.v3_gorivo;
create trigger trg_v3_gorivo_log_delta_history
after update of trenutno_stanje_litri, brojac_pistolj_litri, dug_iznos on public.v3_gorivo
for each row
execute function public.v3_gorivo_log_delta_history();

-- Backfill: postojeće dopune dobijaju procenjen račun sipanja (litri × cena).
update public.v3_gorivo_istorija
set dug_promena = round(litri * cena_po_litru, 2)
where vrsta = 'dopuna'
  and dug_promena is null
  and cena_po_litru is not null;
