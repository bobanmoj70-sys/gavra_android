create table if not exists public.v3_gorivo (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  aktivno boolean not null default true
);
