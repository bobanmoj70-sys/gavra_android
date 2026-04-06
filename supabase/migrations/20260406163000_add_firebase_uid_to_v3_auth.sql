alter table if exists public.v3_auth
  add column if not exists firebase_uid text;

create unique index if not exists v3_auth_firebase_uid_key
  on public.v3_auth (firebase_uid)
  where firebase_uid is not null;
