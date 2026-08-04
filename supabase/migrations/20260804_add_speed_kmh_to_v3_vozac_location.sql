-- Trenutna brzina vozača (km/h) iz GPS fix-a pri tracking tick-u.
-- null = GPS nije dao validan speed (npr. prvi fix / slab signal).
alter table public.v3_vozac_location
  add column if not exists speed_kmh double precision null;

comment on column public.v3_vozac_location.speed_kmh is
  'Trenutna brzina u km/h iz GPS fix-a. Null ako nije dostupna.';
