-- PIN brute-force zastita + audit log za istiskivanje uredjaja (device slot replace)

alter table public.v3_auth
  add column if not exists pin_attempts int not null default 0,
  add column if not exists pin_locked_until timestamptz;

create table if not exists public.v3_device_events (
  id uuid primary key default gen_random_uuid(),
  v3_auth_id uuid not null references public.v3_auth(id) on delete cascade,
  event_type text not null, -- 'slot_replaced_pin_verified'
  replaced_slot int,
  replaced_installation_id text,
  replaced_push_token text,
  new_installation_id text,
  created_at timestamptz not null default now()
);

alter table public.v3_device_events enable row level security;

create policy "Allow all" on public.v3_device_events
  for all to authenticated, anon using (true) with check (true);

create index if not exists idx_v3_device_events_auth_id on public.v3_device_events(v3_auth_id);
