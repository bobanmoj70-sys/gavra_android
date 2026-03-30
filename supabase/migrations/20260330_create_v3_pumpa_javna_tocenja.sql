create table if not exists public.v3_pumpa_javna_tocenja (
  id uuid not null default gen_random_uuid(),
  datum_vreme timestamp with time zone not null default now(),
  vreme_sipanja_min integer null,
  kolicina_l numeric(10, 2) not null default 0.00,
  iznos_rsd numeric(12, 2) not null default 0.00,
  vozac_id uuid null,
  placeno boolean not null default false,
  aktivno boolean null default true,
  created_at timestamp with time zone null default now(),
  updated_at timestamp with time zone null default now(),
  created_by text null,
  updated_by text null,
  constraint v3_pumpa_javna_tocenja_pkey primary key (id)
) tablespace pg_default;

create index if not exists idx_v3_pumpa_javna_tocenja_datum_vreme on public.v3_pumpa_javna_tocenja using btree (datum_vreme desc);
create index if not exists idx_v3_pumpa_javna_tocenja_vozac_id on public.v3_pumpa_javna_tocenja using btree (vozac_id);

create or replace trigger tr_v3_pumpa_javna_tocenja_updated_at
before update on public.v3_pumpa_javna_tocenja
for each row
execute function set_updated_at();
