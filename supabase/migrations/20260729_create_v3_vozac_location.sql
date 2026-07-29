-- Jedna trenutna GPS lokacija po vozaču — jedini izvor istine.
-- Vozačeva aplikacija ažurira ovaj red svakih 20 sekundi (upsert).
-- Nema istorije; prethodna lokacija se uvek prepisuje.
create table if not exists public.v3_vozac_location (
  vozac_id uuid primary key references public.v3_auth(id) on delete cascade,
  lat double precision not null,
  lng double precision not null,
  updated_at timestamp with time zone not null default now()
);

comment on table public.v3_vozac_location is 'Jedna trenutna GPS lokacija po vozaču. Ažurira je Flutter app svakih 20s. JEDINI izvor istine za lokaciju vozača.';
comment on column public.v3_vozac_location.vozac_id is 'ID vozača (v3_auth). Jedan red po vozaču.';
comment on column public.v3_vozac_location.lat is 'Geografska širina.';
comment on column public.v3_vozac_location.lng is 'Geografska dužina.';
comment on column public.v3_vozac_location.updated_at is 'Vreme poslednjeg ažuriranja lokacije.';

-- Dovoljne dozvole za anon/authenticated (RLS se ne koristi za ovu tabelu u praksi,
-- ali dozvoljavamo pristup da ne bismo imali probleme sa permission-ima).
alter table public.v3_vozac_location enable row level security;

create policy if not exists "Allow all on v3_vozac_location"
  on public.v3_vozac_location
  for all
  to anon, authenticated
  using (true)
  with check (true);

-- Indeks za slučajne upite po vremenu ažuriranja (npr. "aktivni vozači").
create index if not exists idx_v3_vozac_location_updated_at
  on public.v3_vozac_location(updated_at desc);
