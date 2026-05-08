create or replace function public.v3_seed_bc_kapacitet_defaults_for_week(p_week_start date)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day date;
  v_offset int;
begin
  if p_week_start is null then
    return;
  end if;

  for v_offset in 0..4 loop
    v_day := p_week_start + v_offset;

    insert into public.v3_kapacitet_slots (grad, vreme, datum, max_mesta)
    values
      ('BC', '05:00', v_day, 9),
      ('BC', '06:00', v_day, 14),
      ('BC', '07:00', v_day, 20),
      ('BC', '08:00', v_day, 9),
      ('BC', '09:00', v_day, 9),
      ('BC', '11:00', v_day, 9),
      ('BC', '12:00', v_day, 9),
      ('BC', '13:00', v_day, 9),
      ('BC', '14:00', v_day, 9),
      ('BC', '15:30', v_day, 9),
      ('BC', '18:00', v_day, 9),
      ('VS', '06:00', v_day, 9),
      ('VS', '07:00', v_day, 9),
      ('VS', '08:00', v_day, 9),
      ('VS', '10:00', v_day, 9),
      ('VS', '11:00', v_day, 9),
      ('VS', '12:00', v_day, 9),
      ('VS', '13:00', v_day, 9),
      ('VS', '14:00', v_day, 18),
      ('VS', '15:30', v_day, 9),
      ('VS', '16:30', v_day, 12),
      ('VS', '19:00', v_day, 12)
    on conflict (grad, vreme, datum)
    do update set max_mesta = excluded.max_mesta;
  end loop;
end;
$$;

create or replace function public.v3_seed_bc_kapacitet_defaults_from_settings()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_week_start date;
begin
  if new.id <> 'global' then
    return new;
  end if;

  v_week_start := coalesce(new.active_week_start::date, current_date);
  perform public.v3_seed_bc_kapacitet_defaults_for_week(v_week_start);

  return new;
end;
$$;

drop trigger if exists trg_v3_seed_bc_kapacitet_defaults_on_settings on public.v3_app_settings;
create trigger trg_v3_seed_bc_kapacitet_defaults_on_settings
after insert or update of active_week_start on public.v3_app_settings
for each row
execute function public.v3_seed_bc_kapacitet_defaults_from_settings();

do $$
declare
  v_week_start date;
begin
  select coalesce(active_week_start::date, current_date)
    into v_week_start
  from public.v3_app_settings
  where id = 'global'
  limit 1;

  if v_week_start is not null then
    perform public.v3_seed_bc_kapacitet_defaults_for_week(v_week_start);
  end if;
end;
$$;