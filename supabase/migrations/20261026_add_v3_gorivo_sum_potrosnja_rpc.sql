-- Server-side suma potrošnje goriva za period [p_start, p_end).
-- PostgREST na ovom projektu odbija agregate u select-u (PGRST123),
-- pa klijent umesto `litri.sum()` poziva ovu funkciju.
-- Redovi sa source='inicijalni_import' su baseline (lifetime brojač pri
-- importu) i ne računaju se kao potrošnja perioda.
create or replace function public.v3_gorivo_sum_potrosnja(
  p_start timestamptz,
  p_end timestamptz
)
returns numeric
language sql
stable
set search_path to 'public'
as $$
  select coalesce(sum(litri), 0)
  from public.v3_gorivo_istorija
  where vrsta = 'potrosnja'
    and created_at >= p_start
    and created_at < p_end
    and coalesce(source, '') <> 'inicijalni_import';
$$;
