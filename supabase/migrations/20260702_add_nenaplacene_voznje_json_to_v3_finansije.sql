alter table public.v3_finansije
add column if not exists nenaplacene_voznje_json jsonb not null default '[]'::jsonb;