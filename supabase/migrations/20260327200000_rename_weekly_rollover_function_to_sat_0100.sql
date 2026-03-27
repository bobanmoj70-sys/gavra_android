-- Rename/alias weekly rollover function to clearer SAT name
-- Keep backward compatibility with old fn_v3_weekly_rollover_fri_0100 name

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_v3_weekly_rollover_sat_0100(
  p_force boolean default false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
BEGIN
  RETURN public.fn_v3_weekly_rollover_fri_0100(p_force);
END;
$function$;

DO $$
DECLARE
  v_job integer;
BEGIN
  SELECT jobid INTO v_job
  FROM cron.job
  WHERE jobname = 'weekly-rollover-sat-0100-belgrade'
  LIMIT 1;

  IF v_job IS NOT NULL THEN
    PERFORM cron.unschedule(v_job);
  END IF;

  PERFORM cron.schedule(
    'weekly-rollover-sat-0100-belgrade',
    '*/5 * * * *',
    'SELECT public.fn_v3_weekly_rollover_sat_0100();'
  );
EXCEPTION
  WHEN undefined_table OR undefined_function THEN
    RAISE NOTICE 'pg_cron nije dostupan; scheduling preskočen.';
END
$$;

COMMIT;

-- Provera:
-- SELECT public.fn_v3_weekly_rollover_sat_0100(false);
-- SELECT public.fn_v3_weekly_rollover_fri_0100(false);
-- SELECT jobname, schedule, command FROM cron.job WHERE jobname='weekly-rollover-sat-0100-belgrade';
