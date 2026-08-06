-- Nadogradnja seed_kapacitet_slots_for_active_week:
-- Pored brisanja starih slotova (datum < active_week_start) i insert-a novih
-- iz bc_custom_by_day / vs_custom_by_day, sada i uklanja orphan slotove
-- unutar aktivne radne nedelje (Pon-Pet) koji vise nisu u custom rasporedu.
-- Tako su v3_kapacitet_slots i "Uredi custom vremena" potpuno uskladjeni
-- i pri dodavanju i pri uklanjanju vremena (max_mesta na preostalim slotovima
-- i dalje ostaje sacuvan zbog ON CONFLICT DO NOTHING).
--
-- Napomena: WITH ORDINALITY daje bigint; date + bigint nije validan u PG,
-- pa se (ordinality - 1) eksplicitno cast-uje na int.

CREATE OR REPLACE FUNCTION public.seed_kapacitet_slots_for_active_week(p_week_start date DEFAULT NULL::date)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
declare
  v_week_start date;
  v_bc jsonb;
  v_vs jsonb;
  v_day text;
  v_day_idx int;
  v_time text;
  v_inserted int := 0;
  v_rows int := 0;
  v_deleted int := 0;
  v_orphans int := 0;
begin
  select
    coalesce(p_week_start, active_week_start),
    coalesce(bc_custom_by_day, '{}'::jsonb),
    coalesce(vs_custom_by_day, '{}'::jsonb)
  into v_week_start, v_bc, v_vs
  from public.v3_app_settings
  where id = 'global'
  limit 1;

  if v_week_start is null then
    return 0;
  end if;

  -- Obrisi stare slotove (pre pocetka aktivne nedelje) - ne treba nam istorija.
  delete from public.v3_kapacitet_slots
  where datum < v_week_start;
  get diagnostics v_deleted = row_count;
  if v_deleted > 0 then
    raise notice 'seed_kapacitet_slots_for_active_week: obrisano % starih slotova pre %', v_deleted, v_week_start;
  end if;

  -- Obrisi orphan slotove aktivne radne nedelje (Pon-Pet) koji nisu u custom rasporedu.
  -- Ručno uneti max_mesta na validnim vremenima se ne dira.
  with expected as (
    select
      g.grad,
      t.vreme_txt::time as vreme,
      (v_week_start + ((d.ordinality - 1)::int))::date as datum
    from unnest(array['Ponedeljak','Utorak','Sreda','Cetvrtak','Petak'])
         with ordinality as d(day_name, ordinality)
    cross join lateral (
      values
        ('BC'::text, coalesce(v_bc -> d.day_name, '[]'::jsonb)),
        ('VS'::text, coalesce(v_vs -> d.day_name, '[]'::jsonb))
    ) as g(grad, times_json)
    cross join lateral jsonb_array_elements(g.times_json) as x(value)
    cross join lateral (select trim(x.value #>> '{}') as vreme_txt) t
    where t.vreme_txt ~ '^\d{1,2}:\d{2}(:\d{2})?$'
  )
  delete from public.v3_kapacitet_slots ks
  where ks.datum >= v_week_start
    and ks.datum <= (v_week_start + 4)
    and not exists (
      select 1
      from expected e
      where e.grad = ks.grad
        and e.vreme = ks.vreme
        and e.datum = ks.datum
    );
  get diagnostics v_orphans = row_count;
  if v_orphans > 0 then
    raise notice 'seed_kapacitet_slots_for_active_week: obrisano % orphan slotova van custom rasporeda', v_orphans;
  end if;

  for v_day_idx, v_day in
    select ordinality::int, day_name
    from unnest(array['Ponedeljak','Utorak','Sreda','Cetvrtak','Petak']) with ordinality as t(day_name, ordinality)
  loop
    for v_time in
      select trim(x.value #>> '{}')
      from jsonb_array_elements(coalesce(v_bc -> v_day, '[]'::jsonb)) as x(value)
    loop
      begin
        insert into public.v3_kapacitet_slots (grad, vreme, datum, max_mesta)
        values ('BC', v_time::time, (v_week_start + (v_day_idx - 1)), 9)
        on conflict (grad, vreme, datum) do nothing;
        get diagnostics v_rows = row_count;
        v_inserted := v_inserted + v_rows;
      exception when others then
        continue;
      end;
    end loop;

    for v_time in
      select trim(x.value #>> '{}')
      from jsonb_array_elements(coalesce(v_vs -> v_day, '[]'::jsonb)) as x(value)
    loop
      begin
        insert into public.v3_kapacitet_slots (grad, vreme, datum, max_mesta)
        values ('VS', v_time::time, (v_week_start + (v_day_idx - 1)), 9)
        on conflict (grad, vreme, datum) do nothing;
        get diagnostics v_rows = row_count;
        v_inserted := v_inserted + v_rows;
      exception when others then
        continue;
      end;
    end loop;
  end loop;

  return v_inserted;
end;
$function$;

COMMENT ON FUNCTION public.seed_kapacitet_slots_for_active_week(date) IS
  'Sinhronizuje v3_kapacitet_slots sa custom rasporedom (bc/vs_custom_by_day): brise stare nedelje, brise orphan slotove aktivne Pon-Pet nedelje koji nisu u custom vremenima, i zasejava nedostajuce slotove (default max_mesta=9, postojece ne prepisuje). Poziva se pri cuvanju custom vremena i nedeljno preko pg_cron.';
