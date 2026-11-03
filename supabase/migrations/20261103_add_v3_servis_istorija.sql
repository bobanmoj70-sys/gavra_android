create table if not exists public.v3_servis_istorija (
  id uuid primary key default gen_random_uuid(),
  vozilo_id uuid not null references public.v3_vozila(id) on delete cascade,
  tip text not null,
  datum date not null,
  km integer,
  created_at timestamptz not null default now()
);

comment on table public.v3_servis_istorija is 'Istorija servisa i zamena po vozilu za računanje prosečnih intervala (dani/km).';
comment on column public.v3_servis_istorija.tip is 'mali_servis | veliki_servis | alternator | akumulator | plocice_prednje | plocice_zadnje | trap | gume_prednje | gume_zadnje';

create index if not exists idx_v3_servis_istorija_vozilo_tip_datum
  on public.v3_servis_istorija (vozilo_id, tip, datum);

alter table public.v3_servis_istorija enable row level security;

drop policy if exists "anon_all_v3_servis_istorija" on public.v3_servis_istorija;
create policy "anon_all_v3_servis_istorija"
  on public.v3_servis_istorija
  for all
  to anon
  using (true)
  with check (true);

drop policy if exists "authenticated_all_v3_servis_istorija" on public.v3_servis_istorija;
create policy "authenticated_all_v3_servis_istorija"
  on public.v3_servis_istorija
  for all
  to authenticated
  using (true)
  with check (true);

-- Backfill: trenutno sačuvane (poslednje) vrednosti servisa postaju početna stavka istorije,
-- pa sledeći unos odmah daje prvi interval za prosek.
insert into public.v3_servis_istorija (vozilo_id, tip, datum, km)
select v.id, t.tip,
       case t.tip
         when 'mali_servis' then v.mali_servis_datum
         when 'veliki_servis' then v.veliki_servis_datum
         when 'alternator' then v.alternator_datum
         when 'akumulator' then v.akumulator_datum
         when 'plocice_prednje' then v.plocice_prednje_datum
         when 'plocice_zadnje' then v.plocice_zadnje_datum
         when 'trap' then v.trap_datum
         when 'gume_prednje' then v.gume_prednje_datum
         when 'gume_zadnje' then v.gume_zadnje_datum
       end,
       case t.tip
         when 'mali_servis' then v.mali_servis_km
         when 'veliki_servis' then v.veliki_servis_km
         when 'alternator' then v.alternator_km
         when 'akumulator' then v.akumulator_km
         when 'plocice_prednje' then v.plocice_prednje_km
         when 'plocice_zadnje' then v.plocice_zadnje_km
         when 'trap' then v.trap_km
         when 'gume_prednje' then v.gume_prednje_km
         when 'gume_zadnje' then v.gume_zadnje_km
       end
from public.v3_vozila v
cross join (values
  ('mali_servis'), ('veliki_servis'), ('alternator'), ('akumulator'),
  ('plocice_prednje'), ('plocice_zadnje'), ('trap'),
  ('gume_prednje'), ('gume_zadnje')
) as t(tip)
where case t.tip
        when 'mali_servis' then v.mali_servis_datum
        when 'veliki_servis' then v.veliki_servis_datum
        when 'alternator' then v.alternator_datum
        when 'akumulator' then v.akumulator_datum
        when 'plocice_prednje' then v.plocice_prednje_datum
        when 'plocice_zadnje' then v.plocice_zadnje_datum
        when 'trap' then v.trap_datum
        when 'gume_prednje' then v.gume_prednje_datum
        when 'gume_zadnje' then v.gume_zadnje_datum
      end is not null;
