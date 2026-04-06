-- AUTH FRESH START: original auth.users + blizanac public.v3_auth
-- Fokus: telefon gate + auth_id FK veza + sigurne RPC funkcije

begin;

create extension if not exists pgcrypto;

create table if not exists public.v3_auth (
  id uuid primary key default gen_random_uuid(),
  auth_id uuid null,
  telefon text not null,
  created_at timestamptz not null default now()
);

-- 1) FK i integritet veze ka original auth.users
alter table public.v3_auth
  drop constraint if exists v3_auth_auth_id_fkey;

alter table public.v3_auth
  add constraint v3_auth_auth_id_fkey
  foreign key (auth_id)
  references auth.users(id)
  on delete cascade;

do $$
begin
  perform 1
  from information_schema.table_constraints
  where table_schema = 'public'
    and table_name = 'v3_auth'
    and constraint_name = 'v3_auth_auth_id_fkey';

  if not found then
    alter table public.v3_auth
      add constraint v3_auth_auth_id_fkey
      foreign key (auth_id)
      references auth.users(id)
      on delete cascade;
  end if;
end $$;

-- 2) Jedan auth user <-> jedan red u blizancu
create unique index if not exists v3_auth_auth_id_unique_not_null
  on public.v3_auth(auth_id)
  where auth_id is not null;

create unique index if not exists v3_auth_telefon_unique
  on public.v3_auth(telefon);

-- 3) Normalizovan telefon (srpske varijante) za sigurno poređenje
create or replace function public.v3_normalize_phone(p_telefon text)
returns text
language plpgsql
immutable
as $$
declare
  raw text;
begin
  raw := regexp_replace(coalesce(p_telefon, ''), '[^0-9+]', '', 'g');

  if raw = '' then
    return '';
  end if;

  if left(raw, 1) = '+' then
    raw := '+' || replace(substring(raw from 2), '+', '');
  else
    raw := replace(raw, '+', '');
  end if;

  if raw like '+381%' then
    return raw;
  elsif raw like '00381%' then
    return '+381' || substring(raw from 6);
  elsif raw like '381%' then
    return '+' || raw;
  elsif raw like '0%' then
    return '+381' || substring(raw from 2);
  end if;

  return raw;
end;
$$;

create unique index if not exists v3_auth_telefon_normalized_unique
  on public.v3_auth(public.v3_normalize_phone(telefon));

-- 4) RLS: zatvori direktan pristup, koristi RPC
alter table public.v3_auth enable row level security;

drop policy if exists "Dozvoli_anon_citanje_za_proveru" on public.v3_auth;
drop policy if exists "v3_auth_select_own_row" on public.v3_auth;

create policy "v3_auth_select_own_row"
on public.v3_auth
for select
to authenticated
using (auth_id = auth.uid());

-- 5) RPC: postoji li telefon u blizancu (gate korak)
create or replace function public.v3_auth_phone_exists(p_telefon text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  return exists (
    select 1
    from public.v3_auth a
    where public.v3_normalize_phone(a.telefon) = public.v3_normalize_phone(p_telefon)
  );
end;
$$;

grant execute on function public.v3_auth_phone_exists(text) to anon, authenticated;

-- 6) RPC: posle magic-link potvrde upari trenutnog auth korisnika sa telefonom
create or replace function public.v3_auth_link_current_user(p_telefon text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_uid uuid;
  target_id uuid;
  target_auth_id uuid;
begin
  current_uid := auth.uid();

  if current_uid is null then
    return false;
  end if;

  select id, auth_id
    into target_id, target_auth_id
  from public.v3_auth
  where public.v3_normalize_phone(telefon) = public.v3_normalize_phone(p_telefon)
  limit 1;

  if target_id is null then
    return false;
  end if;

  if target_auth_id is null then
    update public.v3_auth
       set auth_id = current_uid
     where id = target_id
       and auth_id is null;
    return true;
  end if;

  return target_auth_id = current_uid;
end;
$$;

grant execute on function public.v3_auth_link_current_user(text) to authenticated;

commit;