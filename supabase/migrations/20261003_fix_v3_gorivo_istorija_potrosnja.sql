-- Ispravna potrošnja u v3_gorivo_istorija:
-- 1) potrosnja = stvarno skinute litre iz rezervoara kad poraste brojač pištolja
--    (ne sirova delta brojača koja može da "potroši" više nego što ima u tanku)
-- 2) dopuna se loguje samo kad se menja stanje rezervoara BEZ promene brojača
--    (dopuna cisterne / ručna korekcija naviše)

create or replace function public.v3_gorivo_log_delta_history()
returns trigger
language plpgsql
set search_path to 'public'
as $$
declare
  potrosnja_delta numeric(12,3) := 0;
  dopuna_delta numeric(12,3) := 0;
  brojac_porastao boolean;
begin
  brojac_porastao :=
    coalesce(new.brojac_pistolj_litri, 0) > coalesce(old.brojac_pistolj_litri, 0);

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
    insert into public.v3_gorivo_istorija (gorivo_id, vrsta, litri, cena_po_litru, source)
    values (
      new.id::text,
      'dopuna',
      dopuna_delta,
      nullif(new.cena_po_litru, 0),
      'rezervoar_plus'
    );
  end if;

  return new;
end;
$$;

comment on function public.v3_gorivo_log_delta_history() is
  'Log potrošnje = stvarni pad rezervoara pri porastu brojača; dopuna = rast rezervoara bez promene brojača.';
