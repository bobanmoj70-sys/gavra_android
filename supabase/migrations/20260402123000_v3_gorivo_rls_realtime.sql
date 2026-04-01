alter table public.v3_gorivo enable row level security;
alter table public.v3_gorivo_promene enable row level security;

-- v3_gorivo policies

drop policy if exists v3_gorivo_select on public.v3_gorivo;
create policy v3_gorivo_select
on public.v3_gorivo
for select
to anon, authenticated
using (true);

drop policy if exists v3_gorivo_insert on public.v3_gorivo;
create policy v3_gorivo_insert
on public.v3_gorivo
for insert
to authenticated
with check (true);

drop policy if exists v3_gorivo_update on public.v3_gorivo;
create policy v3_gorivo_update
on public.v3_gorivo
for update
to authenticated
using (true)
with check (true);

drop policy if exists v3_gorivo_delete on public.v3_gorivo;
create policy v3_gorivo_delete
on public.v3_gorivo
for delete
to authenticated
using (true);

-- v3_gorivo_promene policies

drop policy if exists v3_gorivo_promene_select on public.v3_gorivo_promene;
create policy v3_gorivo_promene_select
on public.v3_gorivo_promene
for select
to anon, authenticated
using (true);

drop policy if exists v3_gorivo_promene_insert on public.v3_gorivo_promene;
create policy v3_gorivo_promene_insert
on public.v3_gorivo_promene
for insert
to authenticated
with check (true);

drop policy if exists v3_gorivo_promene_update on public.v3_gorivo_promene;
create policy v3_gorivo_promene_update
on public.v3_gorivo_promene
for update
to authenticated
using (true)
with check (true);

drop policy if exists v3_gorivo_promene_delete on public.v3_gorivo_promene;
create policy v3_gorivo_promene_delete
on public.v3_gorivo_promene
for delete
to authenticated
using (true);

-- Realtime setup
alter table public.v3_gorivo replica identity full;
alter table public.v3_gorivo_promene replica identity full;

do $$
begin
	if not exists (
		select 1
		from pg_publication_tables
		where pubname = 'supabase_realtime'
			and schemaname = 'public'
			and tablename = 'v3_gorivo'
	) then
		alter publication supabase_realtime add table public.v3_gorivo;
	end if;

	if not exists (
		select 1
		from pg_publication_tables
		where pubname = 'supabase_realtime'
			and schemaname = 'public'
			and tablename = 'v3_gorivo_promene'
	) then
		alter publication supabase_realtime add table public.v3_gorivo_promene;
	end if;
end
$$;
