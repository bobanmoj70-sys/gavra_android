-- Ako odbijeni ne odgovori na ponudu oslobođenog mesta u 10 minuta,
-- tretiraj kao Ne i ponudi sledećem (isti rok kao alternativa).

CREATE OR REPLACE FUNCTION public.fn_v3_expire_mesto_ponuda()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  r record;
  v_expired integer := 0;
  v_vreme text;
BEGIN
  FOR r IN
    SELECT z.id, z.datum, z.grad, z.trazeni_polazak_at
    FROM public.v3_zahtevi z
    WHERE z.status = 'odbijeno'
      AND COALESCE(z.mesto_ponuda, false) = true
      AND COALESCE(z.mesto_ponuda_odbijena, false) = false
      AND COALESCE(z.mesto_ponuda_at, z.updated_at) <= now() - interval '10 minutes'
  LOOP
    UPDATE public.v3_zahtevi
    SET mesto_ponuda = false,
        mesto_ponuda_odbijena = true,
        mesto_ponuda_at = null,
        updated_at = now()
    WHERE id = r.id
      AND status = 'odbijeno'
      AND COALESCE(mesto_ponuda, false) = true
      AND COALESCE(mesto_ponuda_odbijena, false) = false;

    IF NOT FOUND THEN
      CONTINUE;
    END IF;

    v_expired := v_expired + 1;
    v_vreme := public.v3_norm_hhmm(r.trazeni_polazak_at::text);
    IF r.datum IS NOT NULL AND btrim(coalesce(r.grad, '')) <> '' AND v_vreme <> '' THEN
      BEGIN
        PERFORM public.fn_v3_offer_freed_seats(
          r.datum::date,
          r.grad::text,
          v_vreme
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'fn_v3_expire_mesto_ponuda offer: %', SQLERRM;
      END;
    END IF;
  END LOOP;

  RETURN v_expired;
END;
$function$;

COMMENT ON FUNCTION public.fn_v3_expire_mesto_ponuda() IS
  'Posle 10 minuta bez odgovora na oslobođeno mesto, nudi se sledećem odbijenom.';

GRANT EXECUTE ON FUNCTION public.fn_v3_expire_mesto_ponuda() TO service_role;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'v3-expire-mesto-ponuda') THEN
      PERFORM cron.unschedule('v3-expire-mesto-ponuda');
    END IF;
    PERFORM cron.schedule(
      'v3-expire-mesto-ponuda',
      '* * * * *',
      'SELECT public.fn_v3_expire_mesto_ponuda();'
    );
  END IF;
END $$;
