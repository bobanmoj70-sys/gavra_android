-- Ažuriranje seed_kapacitet_slots_for_active_week funkcije:
-- BC 06:00 -> 8 mesta
-- BC 07:00 -> 10 mesta
-- VS 14:00 -> 9 mesta
-- Ostali slotovi ostaju na 9 mesta

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
  v_max_mesta int;
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
        -- Odredi kapacitet na osnovu vremena
        v_max_mesta := 9; -- default
        if v_time = '06:00' then
          v_max_mesta := 8;
        elsif v_time = '07:00' then
          v_max_mesta := 10;
        end if;

        insert into public.v3_kapacitet_slots (grad, vreme, datum, max_mesta)
        values ('BC', v_time::time, (v_week_start + (v_day_idx - 1)), v_max_mesta)
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
        -- Odredi kapacitet na osnovu vremena
        v_max_mesta := 9; -- default
        if v_time = '14:00' then
          v_max_mesta := 9; -- već je 9, ali eksplicitno za jasnoću
        end if;

        insert into public.v3_kapacitet_slots (grad, vreme, datum, max_mesta)
        values ('VS', v_time::time, (v_week_start + (v_day_idx - 1)), v_max_mesta)
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
  'Brise v3_kapacitet_slots redove starije od aktivne nedelje i zasejava slotove za aktivnu nedelju sa custom default kapacitetima (BC 06:00=8, BC 07:00=10, VS 14:00=9, ostali=9). Poziva se nedeljno preko pg_cron joba seed_kapacitet_slots_active_week.';
