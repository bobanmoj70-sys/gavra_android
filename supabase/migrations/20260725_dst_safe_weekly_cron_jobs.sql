-- Problem: pg_cron radi iskljucivo po UTC vremenu, dok je aplikacija vezana za
-- Europe/Belgrade (koji je leti UTC+2 - CEST, a zimi UTC+1 - CET). Fiksni cron
-- izraz (npr. "0 3 * * 6") zato pogadja 03:00 samo dok vazi trenutni DST offset,
-- a kad se pomeri letnje/zimsko racunanje vremena - posao pocinje da radi u
-- pogresno vreme (npr. u 05:00 ili 04:00 lokalno umesto 03:00).
--
-- Resenje: umesto da cron sam odredjuje "kada je 03:00", cron sada okida
-- wrapper funkcije svakih 5 minuta, a wrapper funkcije proveravaju STVARNO
-- lokalno vreme u Europe/Belgrade zoni (now() at time zone 'Europe/Belgrade')
-- i izvrsavaju posao samo jednom u ciljanom vremenskom prozoru, po danu.
-- Ovo je DST-otporno i radi identicno tokom cele godine.

-- Tabela za pracenje da li je posao vec odradjen danas (sprecava duplo izvrsavanje
-- u okviru istog 5-minutnog prozora).
CREATE TABLE IF NOT EXISTS public.v3_cron_state (
  job_name text PRIMARY KEY,
  last_run_date date
);

COMMENT ON TABLE public.v3_cron_state IS
  'Cuva datum poslednjeg izvrsavanja DST-osetljivih cron poslova (Europe/Belgrade lokalno vreme), da bi se sprecilo duplo izvrsavanje u okviru 5-minutnog prozora provere.';

-- Wrapper za update_active_week: cilj je subota, 03:00 po Europe/Belgrade.
CREATE OR REPLACE FUNCTION public.v3_maybe_update_active_week()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_local_ts timestamp := (now() at time zone 'Europe/Belgrade');
  v_today date := v_local_ts::date;
  v_last_run date;
BEGIN
  -- Ciljni prozor: subota (dow=6), 03:00-03:04:59 lokalno.
  IF extract(dow from v_local_ts) <> 6
     OR v_local_ts::time < time '03:00'
     OR v_local_ts::time >= time '03:05' THEN
    RETURN;
  END IF;

  SELECT last_run_date INTO v_last_run
  FROM public.v3_cron_state WHERE job_name = 'update_active_week';

  IF v_last_run IS NOT DISTINCT FROM v_today THEN
    RETURN; -- vec odradjeno danas
  END IF;

  UPDATE public.v3_app_settings
  SET active_week_start = v_today + INTERVAL '2 days',
      active_week_end = v_today + INTERVAL '8 days'
  WHERE id = 'global';

  INSERT INTO public.v3_cron_state (job_name, last_run_date)
  VALUES ('update_active_week', v_today)
  ON CONFLICT (job_name) DO UPDATE SET last_run_date = excluded.last_run_date;
END;
$$;

COMMENT ON FUNCTION public.v3_maybe_update_active_week IS
  'DST-otporna zamena za direktan cron UPDATE - pokrece se svakih 5 min, ali izvrsava logiku samo jednom, subotom u 03:00 po Europe/Belgrade lokalnom vremenu.';

-- Wrapper za seed_kapacitet_slots_for_active_week: cilj je subota, 03:05 po Europe/Belgrade,
-- odmah nakon update_active_week.
CREATE OR REPLACE FUNCTION public.v3_maybe_seed_kapacitet_slots()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_local_ts timestamp := (now() at time zone 'Europe/Belgrade');
  v_today date := v_local_ts::date;
  v_last_run date;
BEGIN
  -- Ciljni prozor: subota (dow=6), 03:05-03:09:59 lokalno.
  IF extract(dow from v_local_ts) <> 6
     OR v_local_ts::time < time '03:05'
     OR v_local_ts::time >= time '03:10' THEN
    RETURN;
  END IF;

  SELECT last_run_date INTO v_last_run
  FROM public.v3_cron_state WHERE job_name = 'seed_kapacitet_slots_active_week';

  IF v_last_run IS NOT DISTINCT FROM v_today THEN
    RETURN; -- vec odradjeno danas
  END IF;

  PERFORM public.seed_kapacitet_slots_for_active_week();

  INSERT INTO public.v3_cron_state (job_name, last_run_date)
  VALUES ('seed_kapacitet_slots_active_week', v_today)
  ON CONFLICT (job_name) DO UPDATE SET last_run_date = excluded.last_run_date;
END;
$$;

COMMENT ON FUNCTION public.v3_maybe_seed_kapacitet_slots IS
  'DST-otporna zamena za direktan cron poziv seed_kapacitet_slots_for_active_week - pokrece se svakih 5 min, ali izvrsava logiku samo jednom, subotom u 03:05 po Europe/Belgrade lokalnom vremenu (posle update_active_week).';

-- Preregistruj cron jobove: skini stare (koji direktno rade posao na fiksni UTC sat)
-- i zameni ih wrapper pozivima koji rade svakih 5 minuta.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'update_active_week') THEN
      PERFORM cron.unschedule('update_active_week');
    END IF;
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'seed_kapacitet_slots_active_week') THEN
      PERFORM cron.unschedule('seed_kapacitet_slots_active_week');
    END IF;

    PERFORM cron.schedule(
      'update_active_week',
      '*/5 * * * *',
      'SELECT public.v3_maybe_update_active_week();'
    );
    PERFORM cron.schedule(
      'seed_kapacitet_slots_active_week',
      '*/5 * * * *',
      'SELECT public.v3_maybe_seed_kapacitet_slots();'
    );
  END IF;
END $$;
