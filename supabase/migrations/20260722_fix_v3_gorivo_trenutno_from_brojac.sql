-- Ispravka logike računanja trenutnog stanja rezervoara goriva (v3_gorivo).
--
-- Stari (pogrešan) pristup:
--   trenutno_stanje_litri = kapacitet_litri - brojac_pistolj_litri
-- Problem: kapacitet_litri je FIKSAN (3000L, fizička veličina cisterne) i ne raste,
-- dok je brojac_pistolj_litri KUMULATIVNI brojač (kao na benzinskoj pumpi - samo raste
-- tokom celog veka cisterne). Apsolutna formula je zato tačna samo dok brojač ne premaši
-- kapacitet, nakon čega trajno vraća 0 (ili negativan broj -> clamp na 0), brišući realno
-- stanje rezervoara pri svakoj izmeni brojača kroz admin formu.
--
-- Novi (ispravan) pristup je DELTA-baziran:
--   Kada se brojac_pistolj_litri promeni (tura potrošnje), trenutno stanje se umanjuje
--   za razliku (new - old), a ne postavlja se na apsolutnu vrednost.
--   Dopuna cisterne (tura dolaska goriva) i dalje ide kroz direktan UPDATE na
--   trenutno_stanje_litri (iz V3GorivoService.updateRezervoar) i ovaj trigger se za taj
--   slučaj ne okida jer ne menja brojac_pistolj_litri.
--   Rezultat je uvek clamp-ovan između 0 i kapacitet_litri (fizička granica rezervoara).

CREATE OR REPLACE FUNCTION public.v3_gorivo_set_trenutno_from_brojac()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
begin
  -- Na INSERT-u ne diramo trenutno_stanje_litri - koristi se vrednost koja je
  -- eksplicitno poslata (npr. početni podaci ili ručni unos).
  if TG_OP = 'INSERT' then
    return new;
  end if;

  -- Samo kada se brojač pištolja stvarno promenio (tura potrošnje) umanjujemo
  -- trenutno stanje za razliku (delta), a ne računamo apsolutnu vrednost.
  if new.brojac_pistolj_litri is distinct from old.brojac_pistolj_litri then
    new.trenutno_stanje_litri := greatest(
      least(
        coalesce(old.trenutno_stanje_litri, 0)
          - (coalesce(new.brojac_pistolj_litri, 0) - coalesce(old.brojac_pistolj_litri, 0)),
        coalesce(new.kapacitet_litri, old.kapacitet_litri, 0)
      ),
      0
    );
  end if;

  return new;
end;
$function$;

COMMENT ON FUNCTION public.v3_gorivo_set_trenutno_from_brojac() IS
  'Delta-bazirano umanjenje trenutno_stanje_litri kada se promeni kumulativni brojac_pistolj_litri (potrošnja). Kapacitet_litri je fiksna gornja granica (max litara u cisterni), ne koristi se kao apsolutna referenca.';
