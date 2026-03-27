-- =====================================================
-- DISPECER WAKE-ONLY MODE
-- =====================================================
-- Ovo je usklađeno sa stvarnim stanjem baze.
-- U bazi već postoje:
--   - set_zahtev_scheduled_at()
--   - process_pending_zahtevi_slots()
--   - triggeri na public.v3_zahtevi:
--       * zahtev_scheduled_at_trigger
--       * zahtev_to_operativna_trigger
--
-- Wake-only režim: obrada se pokreće isključivo na event
-- (INSERT/UPDATE status/aktivno na v3_zahtevi).

BEGIN;

-- 1) Kompatibilni wrapper za ručno pokretanje iz SQL editora
CREATE OR REPLACE FUNCTION public.process_pending_zahtevi()
RETURNS TABLE (
    processed_count INT,
    approved_count INT,
    alternative_count INT,
    log_message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
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

CREATE OR REPLACE FUNCTION public.manual_process_zahtevi()
RETURNS TABLE (
    processed_count INT,
    approved_count INT,
    alternative_count INT,
    log_message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY SELECT * FROM public.process_pending_zahtevi_slots();
END;
$$;

-- 2a) U wake-only varijanti oslanjamo se na postojeći
-- `zahtev_scheduled_at_trigger` + `set_zahtev_scheduled_at()` tok,
-- i `zahtev_to_operativna_trigger` za transfer u operativnu tabelu.

-- 3) Pregled zahteva koji čekaju obradu
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
AS $$
BEGIN
    RETURN QUERY
    SELECT
        z.id,
        p.ime_prezime,
        p.tip_putnika,
        z.datum,
        z.grad,
        z.zeljeno_vreme,
        z.created_at,
        z.scheduled_at,
        CASE
            WHEN z.scheduled_at > NOW() THEN EXTRACT(EPOCH FROM (z.scheduled_at - NOW()))::INTEGER / 60
            ELSE 0
        END AS remaining_minutes
    FROM v3_zahtevi z
    JOIN v3_putnici p ON p.id = z.putnik_id
    WHERE z.status = 'obrada'
      AND z.aktivno = true
    ORDER BY z.scheduled_at ASC;
END;
$$;

-- 4) Opcionalno čišćenje legacy funkcije iz cron režima
DROP FUNCTION IF EXISTS public.ensure_dispecer_cron_running();
DROP TRIGGER IF EXISTS tr_v3_wake_dispecer_cron ON public.v3_zahtevi;
DROP FUNCTION IF EXISTS public.wake_dispecer_cron_on_zahtev();

COMMIT;

-- Provera:
-- SELECT * FROM public.get_pending_zahtevi_status();
-- SELECT * FROM public.manual_process_zahtevi();
-- SELECT tgname FROM pg_trigger t
-- JOIN pg_class c ON c.oid = t.tgrelid
-- JOIN pg_namespace n ON n.oid = c.relnamespace
-- WHERE NOT t.tgisinternal
--   AND n.nspname = 'public'
--   AND c.relname = 'v3_zahtevi'
-- ORDER BY tgname;