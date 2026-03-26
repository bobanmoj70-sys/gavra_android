-- Hotfix: push event deduplikacija za Edge funkciju send-push-notification
-- Datum: 2026-03-26
-- Cilj: jedan event -> jedno slanje, čak i ako se isti trigger aktivira više puta

create table if not exists public.push_events (
  id bigint generated always as identity primary key,
  event_key text not null,
  event_id text,
  type text,
  entity_id text,
  recipient_id text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create unique index if not exists push_events_event_key_uidx
  on public.push_events (event_key);

create index if not exists push_events_created_at_idx
  on public.push_events (created_at desc);

create index if not exists push_events_type_entity_recipient_idx
  on public.push_events (type, entity_id, recipient_id);

-- Opcioni cleanup (ručno pokretanje):
-- delete from public.push_events where created_at < now() - interval '30 days';
