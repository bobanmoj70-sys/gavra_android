-- =====================================================
-- Repair dispatcher RPC wrappers for PostgREST
-- =====================================================
-- Problem detected:
--  - public.process_pending_zahtevi_slots() exists and works
--  - missing wrappers: manual_process_zahtevi(), process_pending_zahtevi(), get_pending_zahtevi_status()
--
-- This script recreates missing wrappers and grants execute for REST RPC calls.

BEGIN;

-- 1) Wrapper: process_pending_zahtevi()
CREATE OR REPLACE FUNCTION public.process_pending_zahtevi()
RETURNS TABLE (
    processed_count INT,
    approved_count INT,
    alternative_count INT,
    log_message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    pending_obrada INT;
BEGIN
    SELECT COUNT(*)::INT
    INTO pending_obrada
    FROM public.v3_zahtevi z
    WHERE z.status = 'obrada'
      AND COALESCE(z.aktivno, true) = true;

    IF pending_obrada = 0 THEN
        RETURN QUERY SELECT 0, 0, 0, 'Nema pending obrada zahteva';
        RETURN;
    END IF;

    RETURN QUERY SELECT * FROM public.process_pending_zahtevi_slots();
END;
$$;

-- 2) Wrapper: manual_process_zahtevi()
CREATE OR REPLACE FUNCTION public.manual_process_zahtevi()
RETURNS TABLE (
    processed_count INT,
    approved_count INT,
    alternative_count INT,
    log_message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY SELECT * FROM public.process_pending_zahtevi_slots();
END;
$$;

-- 3) Status RPC: get_pending_zahtevi_status()
CREATE OR REPLACE FUNCTION public.get_pending_zahtevi_status()
RETURNS TABLE (
    zahtev_id UUID,
    putnik_ime TEXT,
    tip_putnika TEXT,
    datum DATE,
    grad TEXT,
    zeljeno_vreme TIME,
    created_at TIMESTAMPTZ,
    scheduled_at TIMESTAMPTZ,
    remaining_minutes INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        z.id,
        p.ime_prezime,
        p.tip_putnika,
        z.datum,
        z.grad,
        NULLIF(z.zeljeno_vreme::text, '')::time,
        z.created_at,
        z.scheduled_at,
        CASE
            WHEN z.scheduled_at > NOW() THEN EXTRACT(EPOCH FROM (z.scheduled_at - NOW()))::INTEGER / 60
            ELSE 0
        END AS remaining_minutes
    FROM public.v3_zahtevi z
    JOIN public.v3_putnici p ON p.id = z.putnik_id
    WHERE z.status = 'obrada'
      AND COALESCE(z.aktivno, true) = true
    ORDER BY z.scheduled_at ASC;
END;
$$;

-- 4) Ensure RPC callability via PostgREST roles
GRANT EXECUTE ON FUNCTION public.process_pending_zahtevi() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.manual_process_zahtevi() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_pending_zahtevi_status() TO anon, authenticated, service_role;

COMMIT;

-- 5) Optional: force PostgREST schema cache reload
NOTIFY pgrst, 'reload schema';

-- -----------------------------------------------------
-- Verification queries
-- -----------------------------------------------------
-- SELECT proname, pg_get_function_identity_arguments(p.oid) AS args
-- FROM pg_proc p
-- JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE n.nspname='public'
--   AND proname IN ('process_pending_zahtevi','manual_process_zahtevi','get_pending_zahtevi_status','process_pending_zahtevi_slots')
-- ORDER BY proname;
--
-- REST test examples:
-- POST /rest/v1/rpc/process_pending_zahtevi
-- POST /rest/v1/rpc/manual_process_zahtevi
-- POST /rest/v1/rpc/get_pending_zahtevi_status
