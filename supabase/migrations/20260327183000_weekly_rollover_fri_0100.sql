-- Weekly rollover pipeline (petak 01:00 Europe/Belgrade)
-- 1) arhivira završeni operativni period
-- 2) čisti narednu nedelju u operativnoj tabeli
-- 3) kopira kapacitet slotove (max_mesta) za narednu nedelju
-- 4) šalje push da je zakazivanje otvoreno

BEGIN;

CREATE TABLE IF NOT EXISTS public.v3_weekly_rollover_runs (
  id bigint generated always as identity primary key,
  run_key date not null unique,
  ran_at timestamptz not null default now(),
  source_week_start date not null,
  target_week_start date not null,
  archive_cutoff date not null,
  archived_rows integer not null default 0,
  deleted_rows integer not null default 0,
  cleared_target_rows integer not null default 0,
  copied_slots integer not null default 0,
  push_sent integer not null default 0,
  note text
);

CREATE OR REPLACE FUNCTION public.fn_v3_weekly_rollover_fri_0100(
  p_force boolean default false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_local_now timestamp;
  v_local_date date;
  v_local_time time;
  v_isodow integer;

  v_source_week_start date;
  v_source_week_end date;
  v_target_week_start date;
  v_target_week_end date;
  v_archive_cutoff date;

  v_already_ran boolean := false;

  v_archived_rows integer := 0;
  v_deleted_rows integer := 0;
  v_cleared_target_rows integer := 0;
  v_copied_slots integer := 0;
  v_push_sent integer := 0;
  v_push_log text := null;
BEGIN
  v_local_now := timezone('Europe/Belgrade', now());
  v_local_date := v_local_now::date;
  v_local_time := v_local_now::time;
  v_isodow := extract(isodow from v_local_now);

  IF NOT p_force THEN
    IF v_isodow <> 5 THEN
      RETURN jsonb_build_object(
        'ok', true,
        'skipped', true,
        'reason', 'not_friday',
        'local_now', v_local_now
      );
    END IF;

    IF v_local_time < time '01:00' OR v_local_time >= time '02:00' THEN
      RETURN jsonb_build_object(
        'ok', true,
        'skipped', true,
        'reason', 'outside_window_01_00_02_00',
        'local_now', v_local_now
      );
    END IF;
  END IF;

  v_source_week_start := date_trunc('week', v_local_date::timestamp)::date;
  v_source_week_end := v_source_week_start + 6;
  v_target_week_start := v_source_week_start + 7;
  v_target_week_end := v_target_week_start + 6;
  v_archive_cutoff := v_local_date - 1;

  SELECT EXISTS (
    SELECT 1
    FROM public.v3_weekly_rollover_runs r
    WHERE r.run_key = v_target_week_start
  ) INTO v_already_ran;

  IF v_already_ran AND NOT p_force THEN
    RETURN jsonb_build_object(
      'ok', true,
      'skipped', true,
      'reason', 'already_ran_for_target_week',
      'target_week_start', v_target_week_start
    );
  END IF;

  INSERT INTO public.v3_operativna_nedelja_arhiva (
    id,
    original_op_id,
    putnik_id,
    datum,
    grad,
    vreme,
    status_final,
    pokupljen,
    broj_mesta,
    zeljeno_vreme,
    dodeljeno_vreme,
    pokupljen_vozac_id,
    naplatio_vozac_id,
    otkazao_vozac_id,
    otkazao_putnik_id,
    koristi_sekundarnu,
    adresa_id_override,
    naplata_status,
    iznos_naplacen,
    aktivno,
    arhiviran_datum,
    nedelja_start,
    nedelja_end,
    razlog_arhiviranja,
    original_created_at,
    original_updated_at,
    created_at,
    updated_at
  )
  SELECT
    gen_random_uuid(),
    o.id,
    o.putnik_id,
    o.datum,
    o.grad,
    coalesce(o.dodeljeno_vreme, o.zeljeno_vreme),
    o.status_final,
    o.pokupljen,
    o.broj_mesta,
    o.zeljeno_vreme,
    o.dodeljeno_vreme,
    o.pokupljen_vozac_id,
    o.naplatio_vozac_id,
    o.otkazao_vozac_id,
    o.otkazao_putnik_id,
    o.koristi_sekundarnu,
    o.adresa_id_override,
    o.naplata_status,
    o.iznos_naplacen,
    o.aktivno,
    v_local_date,
    v_source_week_start,
    v_source_week_end,
    'weekly_rollover_fri_0100',
    o.created_at,
    o.updated_at,
    now(),
    now()
  FROM public.v3_operativna_nedelja o
  WHERE o.datum <= v_archive_cutoff
    AND NOT EXISTS (
      SELECT 1
      FROM public.v3_operativna_nedelja_arhiva a
      WHERE a.original_op_id = o.id
        AND a.nedelja_start = v_source_week_start
    );

  GET DIAGNOSTICS v_archived_rows = ROW_COUNT;

  DELETE FROM public.v3_operativna_nedelja o
  WHERE o.datum <= v_archive_cutoff;

  GET DIAGNOSTICS v_deleted_rows = ROW_COUNT;

  DELETE FROM public.v3_operativna_nedelja o
  WHERE o.datum BETWEEN v_target_week_start AND v_target_week_end;

  GET DIAGNOSTICS v_cleared_target_rows = ROW_COUNT;

  DELETE FROM public.v3_kapacitet_slots ks
  WHERE ks.datum BETWEEN v_target_week_start AND v_target_week_end;

  INSERT INTO public.v3_kapacitet_slots (
    id,
    grad,
    vreme,
    datum,
    max_mesta,
    aktivno,
    created_at,
    updated_at
  )
  SELECT
    gen_random_uuid(),
    ks.grad,
    ks.vreme,
    ks.datum + 7,
    ks.max_mesta,
    true,
    now(),
    now()
  FROM public.v3_kapacitet_slots ks
  WHERE ks.datum BETWEEN v_source_week_start AND v_source_week_end
    AND ks.aktivno = true
  ON CONFLICT (grad, vreme, datum)
  DO UPDATE SET
    max_mesta = EXCLUDED.max_mesta,
    aktivno = true,
    updated_at = now();

  GET DIAGNOSTICS v_copied_slots = ROW_COUNT;

  SELECT sent_count, log_message
  INTO v_push_sent, v_push_log
  FROM public.send_daily_reservation_reminder_all_tokens()
  LIMIT 1;

  INSERT INTO public.v3_weekly_rollover_runs (
    run_key,
    source_week_start,
    target_week_start,
    archive_cutoff,
    archived_rows,
    deleted_rows,
    cleared_target_rows,
    copied_slots,
    push_sent,
    note
  ) VALUES (
    v_target_week_start,
    v_source_week_start,
    v_target_week_start,
    v_archive_cutoff,
    v_archived_rows,
    v_deleted_rows,
    v_cleared_target_rows,
    v_copied_slots,
    coalesce(v_push_sent, 0),
    v_push_log
  )
  ON CONFLICT (run_key) DO UPDATE
  SET
    ran_at = now(),
    archived_rows = EXCLUDED.archived_rows,
    deleted_rows = EXCLUDED.deleted_rows,
    cleared_target_rows = EXCLUDED.cleared_target_rows,
    copied_slots = EXCLUDED.copied_slots,
    push_sent = EXCLUDED.push_sent,
    note = EXCLUDED.note;

  RETURN jsonb_build_object(
    'ok', true,
    'local_now', v_local_now,
    'source_week_start', v_source_week_start,
    'target_week_start', v_target_week_start,
    'archive_cutoff', v_archive_cutoff,
    'archived_rows', v_archived_rows,
    'deleted_rows', v_deleted_rows,
    'cleared_target_rows', v_cleared_target_rows,
    'copied_slots', v_copied_slots,
    'push_sent', coalesce(v_push_sent, 0)
  );
END;
$function$;

DO $$
DECLARE
  v_old_job integer;
BEGIN
  SELECT jobid INTO v_old_job
  FROM cron.job
  WHERE jobname = 'weekly-reservation-reminder-sat-1000'
  LIMIT 1;

  IF v_old_job IS NOT NULL THEN
    PERFORM cron.unschedule(v_old_job);
  END IF;

  SELECT jobid INTO v_old_job
  FROM cron.job
  WHERE jobname = 'weekly-rollover-fri-0100-belgrade'
  LIMIT 1;

  IF v_old_job IS NOT NULL THEN
    PERFORM cron.unschedule(v_old_job);
  END IF;

  PERFORM cron.schedule(
    'weekly-rollover-fri-0100-belgrade',
    '*/5 * * * *',
    'SELECT public.fn_v3_weekly_rollover_fri_0100();'
  );
EXCEPTION
  WHEN undefined_table OR undefined_function THEN
    RAISE NOTICE 'pg_cron nije dostupan; scheduling preskočen.';
END
$$;

COMMIT;

-- Ručna provera:
-- SELECT public.fn_v3_weekly_rollover_fri_0100(true);
-- SELECT * FROM public.v3_weekly_rollover_runs ORDER BY ran_at DESC LIMIT 10;
