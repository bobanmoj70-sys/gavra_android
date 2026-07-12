create table public.v3_zahtev_pazara (
  vozac_id uuid primary key references public.v3_auth(id) on delete cascade,
  aktivan boolean not null default false,
  datum date not null,
  updated_at timestamptz not null default now()
);
alter table public.v3_zahtev_pazara enable row level security;
create policy ""Allow all"" on public.v3_zahtev_pazara for all to authenticated, anon using (true) with check (true);
