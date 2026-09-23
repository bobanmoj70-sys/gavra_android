create table if not exists public.v3_gorivo_istorija (
  id uuid primary key default gen_random_uuid(),
  gorivo_id text,
  vrsta text not null check (vrsta in ('potrosnja', 'dopuna', 'korekcija')),
  litri numeric(12,3) not null check (litri >= 0),
  cena_po_litru numeric(12,2),
  dug_promena numeric(12,2),
  napomena text,
  source text,
  created_at timestamptz not null default now()
);

comment on table public.v3_gorivo_istorija is 'Istorija promena goriva za periodične izveštaje potrošnje i dopuna.';
comment on column public.v3_gorivo_istorija.vrsta is 'potrosnja | dopuna | korekcija';
comment on column public.v3_gorivo_istorija.litri is 'Pozitivna količina litara za dati događaj.';

create index if not exists idx_v3_gorivo_istorija_created_at on public.v3_gorivo_istorija (created_at desc);
create index if not exists idx_v3_gorivo_istorija_vrsta_created_at on public.v3_gorivo_istorija (vrsta, created_at desc);

alter table public.v3_gorivo_istorija enable row level security;

drop policy if exists "Autentikovani korisnici imaju pun pristup v3_gorivo_istorija" on public.v3_gorivo_istorija;
create policy "Autentikovani korisnici imaju pun pristup v3_gorivo_istorija"
  on public.v3_gorivo_istorija
  for all
  to authenticated
  using (true)
  with check (true);

create or replace function public.v3_gorivo_log_delta_history()
returns trigger
language plpgsql
as $$
declare
  potrosnja_delta numeric(12,3);
  dopuna_delta numeric(12,3);
begin
  potrosnja_delta := greatest(coalesce(new.brojac_pistolj_litri, 0) - coalesce(old.brojac_pistolj_litri, 0), 0);
  dopuna_delta := greatest(coalesce(new.trenutno_stanje_litri, 0) - coalesce(old.trenutno_stanje_litri, 0), 0);

  if potrosnja_delta > 0 then
    insert into public.v3_gorivo_istorija (gorivo_id, vrsta, litri, source)
    values (new.id::text, 'potrosnja', potrosnja_delta, 'brojac_delta');
  end if;

  if dopuna_delta > 0 then
    insert into public.v3_gorivo_istorija (gorivo_id, vrsta, litri, cena_po_litru, source)
    values (new.id::text, 'dopuna', dopuna_delta, nullif(new.cena_po_litru, 0), 'rezervoar_plus');
  end if;

  return new;
end;
$$;

drop trigger if exists trg_v3_gorivo_log_delta_history on public.v3_gorivo;
create trigger trg_v3_gorivo_log_delta_history
after update of trenutno_stanje_litri, brojac_pistolj_litri on public.v3_gorivo
for each row
execute function public.v3_gorivo_log_delta_history();

do $$
begin
  if exists (
    select 1
    from pg_publication
    where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'v3_gorivo_istorija'
  ) then
    alter publication supabase_realtime add table public.v3_gorivo_istorija;
  end if;
end $$;
