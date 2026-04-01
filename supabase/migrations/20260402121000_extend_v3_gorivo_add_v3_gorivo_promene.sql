alter table public.v3_gorivo
  add column if not exists kapacitet_litri numeric(12,2) not null default 0 check (kapacitet_litri >= 0),
  add column if not exists trenutno_stanje_litri numeric(12,2) not null default 0 check (trenutno_stanje_litri >= 0),
  add column if not exists alarm_nivo_litri numeric(12,2) not null default 0 check (alarm_nivo_litri >= 0),
  add column if not exists brojac_pistolj_litri numeric(12,2) not null default 0 check (brojac_pistolj_litri >= 0),
  add column if not exists cena_po_litru numeric(12,4) not null default 0 check (cena_po_litru >= 0),
  add column if not exists dug_iznos numeric(12,2) not null default 0;

create table if not exists public.v3_gorivo_promene (
  id uuid primary key default gen_random_uuid(),
  gorivo_id uuid not null references public.v3_gorivo(id) on delete cascade,
  tip_promene text not null check (tip_promene in ('dopuna', 'tocenje', 'korekcija')),
  kolicina_litri numeric(12,2) not null check (kolicina_litri > 0),
  cena_po_litru numeric(12,4) check (cena_po_litru is null or cena_po_litru >= 0),
  iznos numeric(14,2) generated always as (round((kolicina_litri * coalesce(cena_po_litru, 0))::numeric, 2)) stored,
  brojac_pre_litri numeric(12,2) check (brojac_pre_litri is null or brojac_pre_litri >= 0),
  brojac_posle_litri numeric(12,2) check (brojac_posle_litri is null or brojac_posle_litri >= 0),
  dug_promena numeric(12,2) not null default 0,
  napomena text,
  datum timestamptz not null default now(),
  created_at timestamptz not null default now(),
  created_by text
);

create index if not exists idx_v3_gorivo_promene_gorivo_id on public.v3_gorivo_promene(gorivo_id);
create index if not exists idx_v3_gorivo_promene_datum_desc on public.v3_gorivo_promene(datum desc);
create index if not exists idx_v3_gorivo_promene_tip on public.v3_gorivo_promene(tip_promene);
