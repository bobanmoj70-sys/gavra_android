-- Dodaje DST-otpornu funkciju za čišćenje starih operativnih podataka
-- Cilj: subota (dow=6), 00:00-03:04 po Europe/Belgrade lokalnom vremenu (noć petak-subota)
-- Briše podatke iz prethodne nedelje koji više nisu potrebni:
--   - v3_zahtevi
--   - v3_trenutna_dodela
--   - v3_trenutna_dodela_slot
--   - v3_operativna_nedelja

-- Wrapper za cleanup_old_operativna_data: cilj je subota, 00:00-03:04 po Europe/Belgrade.
CREATE OR REPLACE FUNCTION public.v3_maybe_cleanup_old_operativna_data()
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
  -- Ciljni prozor: subota (dow=6), 00:00-03:04:59 lokalno.
  IF extract(dow from v_local_ts) <> 6
     OR v_local_ts::time < time '00:00'
     OR v_local_ts::time >= time '03:05' THEN
    RETURN;
  END IF;

  SELECT last_run_date INTO v_last_run
  FROM public.v3_cron_state WHERE job_name = 'cleanup_old_operativna_data';

  IF v_last_run IS NOT DISTINCT FROM v_today THEN
    RETURN; -- vec odradjeno danas
  END IF;

  -- Briše podatke iz prethodne radne nedelje (ponedeljak-petak)
  -- v_today je subota, prethodna radna nedelja: v_today-4 (ponedeljak) do v_today-1 (petak)

  -- 1. v3_zahtevi - briši zahteve iz prethodne radne nedelje
  DELETE FROM public.v3_zahtevi
  WHERE datum::date >= (v_today - INTERVAL '4 days')
    AND datum::date <= (v_today - INTERVAL '1 day');

  -- 2. v3_trenutna_dodela - briši dodele iz prethodne radne nedelje
  DELETE FROM public.v3_trenutna_dodela td
  USING public.v3_operativna_nedelja o
  WHERE td.termin_id = o.id
    AND o.datum::date >= (v_today - INTERVAL '4 days')
    AND o.datum::date <= (v_today - INTERVAL '1 day');

  -- 3. v3_trenutna_dodela_slot - briši slotove iz prethodne radne nedelje
  DELETE FROM public.v3_trenutna_dodela_slot
  WHERE datum::date >= (v_today - INTERVAL '4 days')
    AND datum::date <= (v_today - INTERVAL '1 day');

  -- 4. v3_operativna_nedelja - briše operativne stavke iz prethodne radne nedelje
  DELETE FROM public.v3_operativna_nedelja
  WHERE datum::date >= (v_today - INTERVAL '4 days')
    AND datum::date <= (v_today - INTERVAL '1 day');

  INSERT INTO public.v3_cron_state (job_name, last_run_date)
  VALUES ('cleanup_old_operativna_data', v_today)
  ON CONFLICT (job_name) DO UPDATE SET last_run_date = excluded.last_run_date;
END;
$$;

COMMENT ON FUNCTION public.v3_maybe_cleanup_old_operativna_data IS
  'DST-otporna funkcija za čišćenje starih operativnih podataka - pokrece se svakih 5 min, ali izvrsava logiku samo jednom, subotom u 00:00-03:04 po Europe/Belgrade lokalnom vremenu (noć petak-subota). Briše v3_zahtevi, v3_trenutna_dodela, v3_trenutna_dodela_slot, v3_operativna_nedelja iz prethodne radne nedelje (ponedeljak-petak).';

-- Registruj cron job
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cleanup_old_operativna_data') THEN
      PERFORM cron.unschedule('cleanup_old_operativna_data');
    END IF;

    PERFORM cron.schedule(
      'cleanup_old_operativna_data',
      '*/5 * * * *',
      'SELECT public.v3_maybe_cleanup_old_operativna_data();'
    );
  END IF;
END $$;
