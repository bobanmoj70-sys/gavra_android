create table if not exists public.v3_slot_rezervacije (
  id uuid primary key default gen_random_uuid(),
  datum date not null,
  grad text not null,
  vreme text not null,
  vozac_v3_auth_id uuid not null references public.v3_auth(id) on delete cascade,
  status text not null default 'aktivan',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.v3_auth(id) on delete set null,
  constraint v3_slot_rezervacije_status_check check (status in ('aktivan', 'neaktivan')),
  constraint v3_slot_rezervacije_vreme_check check (vreme ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
  constraint v3_slot_rezervacije_unique_slot unique (datum, grad, vreme)
);

create index if not exists idx_v3_slot_rezervacije_vozac_status
  on public.v3_slot_rezervacije (vozac_v3_auth_id, status);

create index if not exists idx_v3_slot_rezervacije_slot_lookup
  on public.v3_slot_rezervacije (datum, grad, vreme, status);

create or replace function public.v3_slot_rezervacije_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_v3_slot_rezervacije_set_updated_at on public.v3_slot_rezervacije;
create trigger trg_v3_slot_rezervacije_set_updated_at
before update on public.v3_slot_rezervacije
for each row
execute function public.v3_slot_rezervacije_set_updated_at();
