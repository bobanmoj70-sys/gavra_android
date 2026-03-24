-- =====================================================
-- GPS RASPORED: trigger + 15min push notifikacije + cron
-- =====================================================
-- Cilj:
-- 1) Osigurati da v3_gps_raspored automatski popunjava:
--    - adresa/koordinate
--    - polazak_vreme
--    - activation_time (15 min pre polaska)
-- 2) Slati push notifikacije vozaču + putnicima za konkretan termin
--    kada activation_time <= now()
-- 3) Obezbediti idempotentnost preko notification_sent flag-a

BEGIN;

-- -----------------------------------------------------
-- 1) Trigger za auto-popunu na v3_gps_raspored
-- -----------------------------------------------------
DROP TRIGGER IF EXISTS tr_v3_gps_raspored_populate_coordinates ON public.v3_gps_raspored;

CREATE TRIGGER tr_v3_gps_raspored_populate_coordinates
BEFORE INSERT OR UPDATE ON public.v3_gps_raspored
FOR EACH ROW
EXECUTE FUNCTION public.fn_v3_gps_raspored_populate_coordinates();

-- Backfill za postojeće redove (aktivira trigger i popunjava polja)
UPDATE public.v3_gps_raspored
SET updated_at = now()
WHERE
  polazak_vreme IS NULL
  OR activation_time IS NULL
  OR (putnik_id IS NOT NULL AND (pickup_lat IS NULL OR pickup_lng IS NULL OR pickup_naziv IS NULL));

-- -----------------------------------------------------
-- 2) Funkcija za slanje 15-min push notifikacija za konkretan slot
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION public.send_v3_gps_departure_notifications_for_polazak(p_vreme time)
RETURNS TABLE(sent_terms integer, sent_tokens integer, log_message text)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  term_rec RECORD;
  vozac_token text;
  putnik_tokens jsonb;
  putnik_token_count integer;
  putnici_count integer;
  v_title text;
  v_body text;
  cnt_terms integer := 0;
  cnt_tokens integer := 0;
BEGIN
  FOR term_rec IN
    SELECT DISTINCT
      r.vozac_id,
      r.datum,
      r.grad,
      r.vreme,
      r.nav_bar_type,
      r.polazak_vreme,
      r.activation_time
    FROM public.v3_gps_raspored r
    WHERE r.aktivno = true
      AND COALESCE(r.notification_sent, false) = false
      AND r.vreme = p_vreme
      AND r.polazak_vreme IS NOT NULL
      AND r.activation_time IS NOT NULL
      AND r.activation_time <= now()
      AND r.polazak_vreme > now() - interval '20 minutes'
  LOOP
    -- Broj putnika u terminu
    SELECT COUNT(*)::int
    INTO putnici_count
    FROM public.v3_gps_raspored rg
    WHERE rg.vozac_id = term_rec.vozac_id
      AND rg.datum = term_rec.datum
      AND rg.grad = term_rec.grad
      AND rg.vreme = term_rec.vreme
      AND rg.nav_bar_type = term_rec.nav_bar_type
      AND rg.aktivno = true
      AND rg.putnik_id IS NOT NULL;

    -- 1) Push VOZAČU: gps_tracking_start (postojeći app handler)
    SELECT v.push_token
    INTO vozac_token
    FROM public.v3_vozaci v
    WHERE v.id = term_rec.vozac_id
      AND v.aktivno = true
      AND v.push_token IS NOT NULL
      AND v.push_token <> ''
    LIMIT 1;

    IF vozac_token IS NOT NULL THEN
      PERFORM public.notify_push(
        jsonb_build_array(jsonb_build_object('token', vozac_token, 'provider', 'fcm')),
        '🚗 Vožnja kreće - GPS tracking',
        format(
          'Termin %s %s (%s putnika). Drži tracking uključen do poslednjeg pokupljenog.',
          to_char(term_rec.vreme, 'HH24:MI'),
          term_rec.grad,
          putnici_count
        ),
        jsonb_build_object(
          'type', 'gps_tracking_start',
          'vozac_id', term_rec.vozac_id,
          'datum', term_rec.datum,
          'grad', term_rec.grad,
          'polazak_vreme', term_rec.polazak_vreme,
          'vreme', to_char(term_rec.vreme, 'HH24:MI:SS'),
          'putnici_count', putnici_count,
          'nav_bar_type', term_rec.nav_bar_type,
          'action_keep_tracking', 'true'
        )
      );
      cnt_tokens := cnt_tokens + 1;
    END IF;

    -- 2) Push PUTNICIMA: vozač je krenuo + ETA/live tracking hint
    WITH t AS (
      SELECT DISTINCT p.push_token AS token
      FROM public.v3_gps_raspored rg
      JOIN public.v3_putnici p ON p.id = rg.putnik_id
      WHERE rg.vozac_id = term_rec.vozac_id
        AND rg.datum = term_rec.datum
        AND rg.grad = term_rec.grad
        AND rg.vreme = term_rec.vreme
        AND rg.nav_bar_type = term_rec.nav_bar_type
        AND rg.aktivno = true
        AND p.aktivno = true
        AND p.push_token IS NOT NULL
        AND p.push_token <> ''
    )
    SELECT
      COALESCE(jsonb_agg(jsonb_build_object('token', t.token, 'provider', 'fcm')), '[]'::jsonb),
      COUNT(*)::int
    INTO putnik_tokens, putnik_token_count
    FROM t;

    IF putnik_token_count > 0 THEN
      v_title := '🚗 Vozač je krenuo';
      v_body := format(
        'Termin %s %s je aktivan. Kliknite za praćenje uživo.',
        to_char(term_rec.vreme, 'HH24:MI'),
        term_rec.grad
      );

      PERFORM public.notify_push(
        putnik_tokens,
        v_title,
        v_body,
        jsonb_build_object(
          'type', 'v3_putnik_eta_start',
          'vozac_id', term_rec.vozac_id,
          'datum', term_rec.datum,
          'grad', term_rec.grad,
          'vreme', to_char(term_rec.vreme, 'HH24:MI:SS'),
          'nav_bar_type', term_rec.nav_bar_type,
          'enable_eta_widget', 'true',
          'screen', 'v3_putnik_profil'
        )
      );

      cnt_tokens := cnt_tokens + putnik_token_count;
    END IF;

    -- Obeleži ceo termin kao notifikovan (idempotentno)
    UPDATE public.v3_gps_raspored
    SET
      notification_sent = true,
      gps_status = CASE
        WHEN gps_status = 'pending' THEN 'activated'
        ELSE gps_status
      END,
      updated_at = now(),
      updated_by = 'cron:gps-15min-notify'
    WHERE vozac_id = term_rec.vozac_id
      AND datum = term_rec.datum
      AND grad = term_rec.grad
      AND vreme = term_rec.vreme
      AND nav_bar_type = term_rec.nav_bar_type
      AND aktivno = true;

    cnt_terms := cnt_terms + 1;
  END LOOP;

  RETURN QUERY
  SELECT
    cnt_terms,
    cnt_tokens,
    format('GPS 15min notify (%s): termini=%s, tokena=%s', to_char(p_vreme, 'HH24:MI'), cnt_terms, cnt_tokens);
END;
$$;

-- -----------------------------------------------------
-- 3) Generator cron jobova na tačno vreme (polazak - 15 min)
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION public.refresh_v3_gps_departure_cron_jobs()
RETURNS TABLE(created_jobs integer, log_message text)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  old_job RECORD;
  slot_rec RECORD;
  notify_time time;
  cron_expr text;
  job_name text;
  created_count integer := 0;
BEGIN
  -- Ukloni prethodno generisane slot jobove
  FOR old_job IN
    SELECT jobid
    FROM cron.job
    WHERE jobname LIKE 'gps-15min-slot-%'
  LOOP
    PERFORM cron.unschedule(old_job.jobid);
  END LOOP;

  -- Napravi nove jobove po aktivnim slotovima
  FOR slot_rec IN
    SELECT DISTINCT vreme
    FROM public.v3_gps_raspored
    WHERE aktivno = true
    ORDER BY vreme
  LOOP
    notify_time := slot_rec.vreme - interval '15 minutes';

    cron_expr := format(
      '%s %s * * *',
      EXTRACT(MINUTE FROM notify_time)::int,
      EXTRACT(HOUR FROM notify_time)::int
    );

    job_name := format('gps-15min-slot-%s', replace(to_char(slot_rec.vreme, 'HH24:MI'), ':', ''));

    PERFORM cron.schedule(
      job_name,
      cron_expr,
      format(
        'SELECT * FROM public.send_v3_gps_departure_notifications_for_polazak(''%s''::time);',
        to_char(slot_rec.vreme, 'HH24:MI:SS')
      )
    );

    created_count := created_count + 1;
  END LOOP;

  RETURN QUERY
  SELECT created_count, format('Kreirano %s GPS slot cron jobova.', created_count);
END;
$$;

-- Inicijalno kreiranje slot jobova odmah nakon deploy-a
SELECT * FROM public.refresh_v3_gps_departure_cron_jobs();

-- Dnevni refresh (u 00:10) da pokupi eventualne promene termina
DO $$
DECLARE
  old_job_id INT;
BEGIN
  SELECT jobid
  INTO old_job_id
  FROM cron.job
  WHERE jobname = 'gps-15min-refresh';

  IF old_job_id IS NOT NULL THEN
    PERFORM cron.unschedule(old_job_id);
  END IF;
END $$;

SELECT cron.schedule(
  'gps-15min-refresh',
  '10 0 * * *',
  'SELECT * FROM public.refresh_v3_gps_departure_cron_jobs();'
);

COMMIT;

-- Provera nakon primene:
-- SELECT * FROM cron.job WHERE jobname LIKE 'gps-15min-%' ORDER BY jobid;
-- SELECT * FROM public.refresh_v3_gps_departure_cron_jobs();
-- SELECT * FROM public.send_v3_gps_departure_notifications_for_polazak('05:00:00'::time);
-- SELECT id, datum, grad, vreme, polazak_vreme, activation_time, notification_sent, gps_status
-- FROM public.v3_gps_raspored
-- ORDER BY datum, grad, vreme;
