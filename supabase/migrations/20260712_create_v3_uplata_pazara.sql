create table public.v3_uplata_pazara (
  id uuid primary key default gen_random_uuid(),
  vozac_id uuid not null references public.v3_auth(id) on delete cascade,
  mesec int not null,
  godina int not null,
  dnevne_uplate_json jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(vozac_id, mesec, godina)
);

comment on table public.v3_uplata_pazara is 'Mesecna evidencija uplata pazara po vozacu. Dnevne uplate se cuvaju u JSONB nizu.';
comment on column public.v3_uplata_pazara.dnevne_uplate_json is 'Niz dnevnih uplata pazara: [{dan, predao, ukupno, razlika}]';

alter table public.v3_uplata_pazara enable row level security;

create policy "Allow all" on public.v3_uplata_pazara
  for all
  to authenticated, anon
  using (true)
  with check (true);
