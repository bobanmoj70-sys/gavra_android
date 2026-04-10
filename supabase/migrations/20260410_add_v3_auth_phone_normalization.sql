begin;

create or replace function public.normalize_rs_phone(input text)
returns text
language sql
immutable
as $$
  with digits as (
    select regexp_replace(coalesce(input, ''), '\\D', '', 'g') as d
  )
  select case
    when d = '' then ''
    when d like '381%' then d
    when d like '00381%' then substring(d from 3)
    when d like '0%' and char_length(d) >= 7 then '381' || substring(d from 2)
    else d
  end
  from digits;
$$;

do $$
begin
  if to_regclass('public.v3_auth') is null then
    raise notice 'Table public.v3_auth does not exist. Skipping phone normalization migration.';
    return;
  end if;

  alter table public.v3_auth
    add column if not exists telefon_norm text generated always as (public.normalize_rs_phone(telefon)) stored,
    add column if not exists telefon_2_norm text generated always as (public.normalize_rs_phone(telefon_2)) stored;

  create index if not exists v3_auth_telefon_norm_idx on public.v3_auth (telefon_norm);
  create index if not exists v3_auth_telefon_2_norm_idx on public.v3_auth (telefon_2_norm);
end
$$;

commit;
