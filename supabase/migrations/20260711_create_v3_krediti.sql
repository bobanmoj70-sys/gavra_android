create table if not exists public.v3_krediti (
  id uuid primary key default gen_random_uuid(),
  naziv text not null,
  ukupan_iznos numeric(12,2) not null default 0,
  uplaceno numeric(12,2) not null default 0,
  napomena text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

comment on table public.v3_krediti is 'Licna dugovanja firme/vlasnika prema bankama, porodici, dobavljacima i slicno. Razlicita od potrazivanja od putnika.';
comment on column public.v3_krediti.naziv is 'Naziv kredita/dugovanja, npr. Ivana, Mama, BMW, Dizel.';
comment on column public.v3_krediti.ukupan_iznos is 'Ukupan iznos koji treba otplatiti.';
comment on column public.v3_krediti.uplaceno is 'Dosad uplaceni iznos. Preostalo se racuna kao ukupan_iznos - uplaceno.';
comment on column public.v3_krediti.napomena is 'Opcionalna napomena uz kredit.';

-- Ukljuci RLS i dozvoli svim autentikovanim korisnicima pun pristup.
-- Admin provera se vrsi na nivou Flutter UI-ja (hardkodiran UUID).
alter table public.v3_krediti enable row level security;

create policy "Autentikovani korisnici imaju pun pristup v3_krediti"
  on public.v3_krediti
  for all
  to authenticated
  using (true)
  with check (true);

-- Omoguci realtime za novu tabelu
alter publication supabase_realtime add table public.v3_krediti;
