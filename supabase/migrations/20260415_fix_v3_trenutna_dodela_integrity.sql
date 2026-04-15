-- Normalize and harden assignment table integrity

-- 1) Normalize historical status values to Serbian canonical values
update public.v3_trenutna_dodela
set status = case
  when lower(trim(status)) in ('active', 'aktivan') then 'aktivan'
  when lower(trim(status)) in ('inactive', 'neaktivan', 'deleted') then 'neaktivan'
  when lower(trim(status)) in ('cancelled', 'otkazan', 'otkazano') then 'otkazano'
  else 'aktivan'
end;

-- 2) Ensure there is only one row per operativna termin (keep latest)
with ranked as (
  select
    ctid,
    row_number() over (
      partition by termin_id
      order by updated_at desc nulls last, ctid desc
    ) as rn
  from public.v3_trenutna_dodela
)
delete from public.v3_trenutna_dodela t
using ranked r
where t.ctid = r.ctid
  and r.rn > 1;

-- 3) Harden schema defaults and nullability for required assignment fields
alter table public.v3_trenutna_dodela
  alter column status set default 'aktivan',
  alter column termin_id set not null,
  alter column putnik_v3_auth_id set not null,
  alter column vozac_v3_auth_id set not null,
  alter column updated_at set default now();

-- 4) Enforce allowed status domain
alter table public.v3_trenutna_dodela
  drop constraint if exists v3_trenutna_dodela_status_check;

alter table public.v3_trenutna_dodela
  add constraint v3_trenutna_dodela_status_check
  check (status in ('aktivan', 'neaktivan', 'otkazano'));

-- 5) Guarantee one assignment per operativna row
alter table public.v3_trenutna_dodela
  drop constraint if exists v3_trenutna_dodela_pkey;

alter table public.v3_trenutna_dodela
  add constraint v3_trenutna_dodela_pkey primary key (termin_id);

-- 6) Speed up main read paths
create index if not exists idx_v3_trenutna_dodela_vozac_status
  on public.v3_trenutna_dodela (vozac_v3_auth_id, status);

create index if not exists idx_v3_trenutna_dodela_putnik_status
  on public.v3_trenutna_dodela (putnik_v3_auth_id, status);
