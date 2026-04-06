begin;

do $$
declare
  r record;
begin
  for r in
    select
      n.nspname as schema_name,
      p.proname as function_name,
      pg_get_function_identity_arguments(p.oid) as function_args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      and pg_get_functiondef(p.oid) ilike '%v3_pin_zahtevi%'
  loop
    execute format(
      'drop function if exists %I.%I(%s) cascade',
      r.schema_name,
      r.function_name,
      r.function_args
    );
  end loop;
end;
$$;

drop table if exists public.v3_pin_zahtevi cascade;

commit;