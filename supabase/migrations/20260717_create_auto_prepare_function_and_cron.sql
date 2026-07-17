-- Funkcija koja pronalazi termine koji pocinju za 10 minuta i imaju dodeljenog vozaca
CREATE OR REPLACE FUNCTION public.v3_find_termins_for_auto_prepare(
  p_datum date,
  p_start_time text,
  p_end_time text
)
RETURNS TABLE (
  id uuid,
  datum date,
  grad text,
  polazak_at time without time zone,
  created_by uuid,
  vozac_id uuid,
  koristi_sekundarnu boolean,
  adresa_override_id uuid
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT
    o.id,
    o.datum,
    o.grad,
    o.polazak_at,
    o.created_by,
    td.vozac_v3_auth_id AS vozac_id,
    o.koristi_sekundarnu,
    o.adresa_override_id
  FROM public.v3_operativna_nedelja o
  JOIN public.v3_trenutna_dodela td ON td.termin_id = o.id
  WHERE o.datum = p_datum
    AND o.pokupljen_at IS NULL
    AND o.otkazano_at IS NULL
    AND o.polazak_at >= p_start_time::time
    AND o.polazak_at < p_end_time::time
  ORDER BY o.polazak_at, o.grad, td.vozac_v3_auth_id;
$$;

COMMENT ON FUNCTION public.v3_find_termins_for_auto_prepare IS 'Pronalazi termine koji pocinju u zadatom vremenskom prozoru i imaju dodeljenog vozaca';

-- Funkcija koja se poziva iz pg_cron i okida v3-auto-prepare-termins edge funkciju
CREATE OR REPLACE FUNCTION public.v3_trigger_auto_prepare()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_supabase_url text;
  v_anon_key text;
BEGIN
  SELECT decrypted_secret INTO v_supabase_url
  FROM vault.decrypted_secrets
  WHERE name = 'supabase_url'
  ORDER BY updated_at DESC
  LIMIT 1;

  SELECT decrypted_secret INTO v_anon_key
  FROM vault.decrypted_secrets
  WHERE name = 'supabase_anon_key'
  ORDER BY updated_at DESC
  LIMIT 1;

  IF v_supabase_url IS NULL OR v_supabase_url = '' THEN
    RAISE NOTICE 'v3_trigger_auto_prepare: missing supabase_url vault secret';
    RETURN;
  END IF;

  IF v_anon_key IS NULL OR v_anon_key = '' THEN
    RAISE NOTICE 'v3_trigger_auto_prepare: missing supabase_anon_key vault secret';
    RETURN;
  END IF;

  PERFORM net.http_post(
    url := v_supabase_url || '/functions/v1/v3-auto-prepare-termins',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_anon_key,
      'apikey', v_anon_key
    ),
    body := '{}'::jsonb
  );
END;
$$;

COMMENT ON FUNCTION public.v3_trigger_auto_prepare IS 'Poziva v3-auto-prepare-termins edge funkciju svakog minuta';

-- Zakazi cron job da radi svakog minuta
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'v3-auto-prepare-termins') THEN
      PERFORM cron.unschedule('v3-auto-prepare-termins');
    END IF;
    PERFORM cron.schedule(
      'v3-auto-prepare-termins',
      '* * * * *',
      'SELECT public.v3_trigger_auto_prepare();'
    );
  END IF;
END $$;
