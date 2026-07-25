-- Nadogradnja seed_kapacitet_slots_for_active_week funkcije:
-- Pre nego sto se ubace novi slotovi za aktivnu nedelju, brisu se svi
-- v3_kapacitet_slots redovi sa datumom starijim od pocetka aktivne nedelje.
-- Kapacitet slotovi se koriste samo za tekucu/buducu operativnu nedelju
-- (kontrola broja mesta po terminu) i nema potrebe da se cuvaju kao istorija,
-- pa se stare nedelje brisu da ne pune bazu bez potrebe.
--
-- Funkcija se vec poziva jednom nedeljno preko pg_cron joba
-- "seed_kapacitet_slots_active_week" (subota 03:05), odmah nakon sto
-- "update_active_week" (subota 03:00) pomeri active_week_start na novu nedelju,
-- pa je ovo prirodno mesto za ciscenje stare nedelje.

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

  -- Obrisi stare slotove (pre pocetka aktivne nedelje) - ne treba nam istorija,
  -- samo pune bazu bez ikakve koristi.
  delete from public.v3_kapacitet_slots
  where datum < v_week_start;
  get diagnostics v_deleted = row_count;
  if v_deleted > 0 then
    raise notice 'seed_kapacitet_slots_for_active_week: obrisano % starih slotova pre %', v_deleted, v_week_start;
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
  'Brise v3_kapacitet_slots redove starije od aktivne nedelje (nema potrebe za istorijom) i zasejava slotove za aktivnu nedelju. Poziva se nedeljno preko pg_cron joba seed_kapacitet_slots_active_week.';
